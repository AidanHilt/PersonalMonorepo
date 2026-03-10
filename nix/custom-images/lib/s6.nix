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
      mkdir -p $out/etc/sv/${name}

      # run script
      cat > $out/etc/sv/${name}/run << 'EOF'
      #!/bin/sh
      ${run}
      EOF
      chmod +x $out/etc/sv/${name}/run

      # type file — tells s6 this is a longrun service
      echo "longrun" > $out/etc/sv/${name}/type

      ${pkgs.lib.optionalString (finish != null) ''
        cat > $out/etc/sv/${name}/finish << 'EOF'
        #!/bin/sh
        ${finish}
        EOF
        chmod +x $out/etc/sv/${name}/finish
      ''}

      ${pkgs.lib.optionalString log ''
        # s6 uses a separate logger service in a subdirectory
        mkdir -p $out/etc/sv/${name}/log

        # type file for the logger
        echo "longrun" > $out/etc/sv/${name}/log/type

        cat > $out/etc/sv/${name}/log/run << 'EOF'
        #!/bin/sh
        mkdir -p ${logDir}
        exec ${pkgs.s6}/bin/s6-log -d3 t ${logDir}
        EOF
        chmod +x $out/etc/sv/${name}/log/run

        # producer-for tells s6 this logger belongs to the parent service
        echo "${name}" > $out/etc/sv/${name}/log/producer-for
      ''}
    '';
in
{
  mkService = mkService;
}