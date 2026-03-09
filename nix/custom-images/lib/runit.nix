{ pkgs, tag, ... }:

let
  mkService =
    { name,          # string  — used as the directory name under /etc/sv
    run,           # string  — shell body of the run script
    finish ? null, # string? — shell body of the finish script (optional)
    log  ? true,   # bool    — whether to attach a svlogd log service
    logDir ? "/var/log/${name}" # where svlogd writes logs
    }:
    pkgs.runCommand "sv-${name}" {} ''
      mkdir -p $out

      # run — must exec (not just call) the process so runsv owns the PID
      cat > $out/run << 'EOF'
      #!/bin/sh
      ${run}
      EOF
      chmod +x $out/run

      ${pkgs.lib.optionalString (finish != null) ''
        cat > $out/finish << 'EOF'
        #!/bin/sh
        ${finish}
        EOF
        chmod +x $out/finish
      ''}

      ${pkgs.lib.optionalString log ''
        mkdir -p $out/log
        cat > $out/log/run << 'EOF'
        #!/bin/sh
        mkdir -p ${logDir}
        exec chpst -u nobody svlogd -tt ${logDir}
        EOF
        chmod +x $out/log/run
      ''}
    '';
in

{

}