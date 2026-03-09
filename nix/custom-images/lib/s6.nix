{ pkgs, tag, ... }:
let
  mkService =
    { name,
      run,
      finish ? null,
      log ? true,
      logDir ? "/var/log/${name}"
    }:
    pkgs.runCommand "s6-${name}" {} ''
      mkdir -p $out

      # run script
      cat > $out/run << 'EOF'
      #!/bin/sh
      ${run}
      EOF
      chmod +x $out/run

      # type file — tells s6 this is a longrun service
      echo "longrun" > $out/type

      ${pkgs.lib.optionalString (finish != null) ''
        cat > $out/finish << 'EOF'
        #!/bin/sh
        ${finish}
        EOF
        chmod +x $out/finish
      ''}

      ${pkgs.lib.optionalString log ''
        # s6 uses a separate logger service in a subdirectory
        mkdir -p $out/log

        # type file for the logger
        echo "longrun" > $out/log/type

        cat > $out/log/run << 'EOF'
        #!/bin/sh
        mkdir -p ${logDir}
        exec ${pkgs.s6}/bin/s6-log -d3 t ${logDir}
        EOF
        chmod +x $out/log/run

        # producer-for tells s6 this logger belongs to the parent service
        echo "${name}" > $out/log/producer-for
      ''}
    '';
in
{
  mkService = mkService;
}