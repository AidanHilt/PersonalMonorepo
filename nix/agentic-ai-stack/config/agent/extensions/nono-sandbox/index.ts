// config/agent/extensions/nono-sandbox/index.ts
//
// Detects a nono sandbox denial (process.env.NONO_CAP_FILE, tool-result
// error patterns) and tells the agent to ask the user to relaunch with
// `start-agent.sh --add <path>` then `pi --resume` -- never to edit
// profiles, profile-drafts, or any nono state itself.
import { existsSync, readFileSync } from "node:fs";
import type { ExtensionAPI, ToolResultEvent } from "@earendil-works/pi-coding-agent";

const DENIAL_PATTERNS = [
	/operation not permitted/i,
	/permission denied/i,
	/\bEACCES\b/i,
	/\bEPERM\b/i,
	/landlock/i,
	/sandbox(?:ed)?:?\s+deny/i,
	/sandbox denied/i,
];

const SYSTEM_CONTEXT = `
You are running inside nono, an outer OS-level sandbox. nono filesystem and network limits are enforced by the operating system before Pi starts. Pi approvals, retries, chmod, chown, sudo, or macOS Full Disk Access cannot grant access that nono has not allowed.

If a tool or shell command fails with Operation not permitted, Permission denied, EACCES, EPERM, landlock, sandbox deny, or sandbox denied, treat it as a nono sandbox boundary. You cannot expand nono access from inside this session, and you must not try to: do not run \`nono run --allow\`, do not draft or edit a profile under ~/.config/nono/profile-drafts/ or anywhere else under ~/.config/nono, and do not attempt to read or modify nono state.

Instead, tell the user exactly what path or host was blocked, and ask them to relaunch with it added, then resume this session:

    start-agent.sh --add /path/to/needed --name <same-session-name>
    (then, once relaunched) pi --resume

Do not suggest sudo, chmod, chown, Full Disk Access, or a Pi approval-system change for this denial -- none of those can grant what nono itself has not allowed.
`.trim();

const DENIAL_GUIDANCE = `

[nono sandbox diagnostic]
This looks like an outer nono sandbox denial, not a Unix permission problem.

Ask the user to relaunch with the needed path added, then resume:
  start-agent.sh --add /path/to/needed --name <same-session-name>
  (then, once relaunched) pi --resume

Do not run \`nono run --allow\` yourself, do not draft or edit a nono profile or profile-draft, and do not suggest sudo, chmod, chown, Full Disk Access, or a Pi approval-system change for this denial.
`.trim();

function insideNono(): boolean {
	return Boolean(process.env.NONO_CAP_FILE);
}

function textFromEvent(event: ToolResultEvent): string {
	return event.content
		.filter((item) => item.type === "text")
		.map((item) => item.text)
		.join("\n");
}

function looksLikeDenial(event: ToolResultEvent): boolean {
	if (!event.isError) return false;
	const haystack = [event.toolName, textFromEvent(event), JSON.stringify(event.details ?? {})].join("\n");
	return DENIAL_PATTERNS.some((pattern) => pattern.test(haystack));
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		if (insideNono() && ctx.hasUI) {
			ctx.ui.setStatus("nono", "nono sandbox");
		}
	});

	pi.on("before_agent_start", async (event) => {
		if (!insideNono()) return undefined;
		return {
			systemPrompt: `${event.systemPrompt}\n\n${SYSTEM_CONTEXT}`,
		};
	});

	pi.on("tool_result", async (event, ctx) => {
		if (!insideNono() || !looksLikeDenial(event)) return undefined;

		if (ctx.hasUI) {
			ctx.ui.notify("nono sandbox denial detected", "warning");
		}

		return {
			content: [
				...event.content,
				{
					type: "text" as const,
					text: DENIAL_GUIDANCE,
				},
			],
			isError: true,
		};
	});

	pi.registerCommand("nono-status", {
		description: "Show nono sandbox status for this Pi session",
		handler: async (_args, ctx) => {
			const capFile = process.env.NONO_CAP_FILE;
			if (!capFile) {
				ctx.ui.notify("Pi is not running inside a nono session.", "info");
				return;
			}

			if (!existsSync(capFile)) {
				ctx.ui.notify(`nono capability file is not readable: ${capFile}`, "warning");
				return;
			}

			const summary = readFileSync(capFile, "utf8")
				.split("\n")
				.slice(0, 12)
				.join("\n")
				.trim();
			ctx.ui.notify(summary || `nono capability file is empty: ${capFile}`, "info");
		},
	});
}
