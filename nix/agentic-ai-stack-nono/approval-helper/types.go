package main

// capabilityInfo mirrors the "request" object inside nono's unsigned
// webhook v1 approval request body. See PLAN.md's "Approval helper (host
// side)"/"Approval transport" decision rows, verified by spike S1.9
// against spikes/all/handler.sh and spikes/all/approval.template.json.
type capabilityInfo struct {
	CapabilityType string   `json:"capability_type"`
	RequestID      string   `json:"request_id"`
	SessionID      string   `json:"session_id"`
	Host           string   `json:"host"`
	Port           int      `json:"port"`
	Protocol       string   `json:"protocol"`
	ResolvedIPs    []string `json:"resolved_ips"`
	Reason         string   `json:"reason"`
	ChildPID       int      `json:"child_pid"`
}

// webhookRequest is the top-level body nono POSTs to the approval
// webhook.
type webhookRequest struct {
	Backend string         `json:"backend"`
	Request capabilityInfo `json:"request"`
}

// webhookResponse is this helper's reply. Decision is one of "granted",
// "denied", or "granted_session"; Reason is only meaningful (and only
// ever set) for "denied".
type webhookResponse struct {
	Decision string `json:"decision"`
	Reason   string `json:"reason,omitempty"`
}

// decision is the internal result of resolving one approval request,
// before it's serialized onto a webhookResponse.
type decision struct {
	Type   string // "granted", "denied", or "granted_session"
	Reason string
}

// startupInfo is the one JSON line this helper prints to stdout (and
// optionally writes to --info-file) once it's listening, so the launcher
// can read back the webhook URL to embed in the generated nono profile.
type startupInfo struct {
	Port  int    `json:"port"`
	Token string `json:"token"`
	URL   string `json:"url"`
}
