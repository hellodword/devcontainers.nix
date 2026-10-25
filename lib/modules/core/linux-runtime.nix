{ pkgs, ... }:
let
  packages = with pkgs; [
    getent
    ncurses
    shared-mime-info
    glib.bin
    dbus
    tini
  ];
in
{
  environment.systemPackages = packages;
  environment.etc = {
    "services".source = "${pkgs.iana-etc}/etc/services";
    "protocols".source = "${pkgs.iana-etc}/etc/protocols";
    "mime.types".source = "${pkgs.mailcap}/etc/mime.types";
    "nsswitch.conf".text = ''
      passwd: files
      group: files
      shadow: files
      hosts: files dns
      networks: files
      services: files
      protocols: files
    '';
    "shells".text = ''
      /bin/sh
      /bin/bash
      /usr/bin/sh
      /usr/bin/bash
    '';
    # nixpkgs builds dbus with /etc as its datadir. Supply a standalone session
    # config, without upstream's legacy include of this same /etc file.
    "dbus-1/session.conf".text = ''
      <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
        "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
      <busconfig>
        <type>session</type>
        <keep_umask/>
        <listen>unix:tmpdir=/tmp</listen>
        <auth>EXTERNAL</auth>
        <standard_session_servicedirs/>
        <policy context="default">
          <allow send_destination="*" eavesdrop="true"/>
          <allow eavesdrop="true"/>
          <allow own="*"/>
        </policy>
        <includedir>/etc/dbus-1/session.d</includedir>
        <include ignore_missing="yes">/etc/dbus-1/session-local.conf</include>
      </busconfig>
    '';
  };

  devcontainer.layers.bucketDefinitions."linux-runtime" = {
    order = 11400;
    owner = "core/linux-runtime";
    purpose = "Linux identity, terminal, MIME and on-demand D-Bus session support.";
  };
  devcontainer.graph.nodes."runtime/linux" = {
    kind = "runtime";
    group = "linux-runtime";
    paths = packages;
    stability = "very-stable";
    sharing = "global";
    priority = 96;
    securityClass = "trusted";
  };
  devcontainer.tests.cases."base.linux-runtime" = {
    tags = [
      "smoke"
      "baseline"
      "base"
      "linux-runtime"
    ];
    scripts = [
      {
        shell = "bash";
        interactive = false;
        command = ''
          set -euo pipefail
          getent passwd vscode
          getent group vscode
          getent hosts localhost
          getent services https
          getent protocols tcp
          for shell in /bin/sh /bin/bash /usr/bin/sh /usr/bin/bash; do
            grep -Fx "$shell" /etc/shells
            test -x "$shell"
          done
          test -d /usr/share/terminfo
          for term in xterm xterm-256color screen-256color; do
            infocmp "$term" >/dev/null
            TERM="$term" tput colors >/dev/null
          done
          test -s /usr/share/mime/mime.cache
          test -s /etc/mime.types
          test -d /usr/share/zoneinfo
          test "$(TZ=Asia/Shanghai date -d @0 +%z)" = +0800
          test "$(TZ=America/New_York date -d @0 +%z)" = -0500
          test "$(stat -c %a /tmp)" = 1777
          test "$(stat -c %a /var/tmp)" = 1777
          test "$(stat -c %a "$XDG_RUNTIME_DIR")" = 700
          test "$(stat -c %u "$XDG_RUNTIME_DIR")" = "$(id -u)"
          cmp /etc/machine-id /var/lib/dbus/machine-id
          dbus-uuidgen --get=/etc/machine-id >/dev/null
          dbus-run-session -- dbus-send --session --print-reply \
            --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames
          sample=$(mktemp --suffix=.png)
          trap 'rm -f "$sample"' EXIT
          printf '\211PNG\r\n\032\n' > "$sample"
          gio info -a standard::content-type "$sample" | grep -F 'image/png'
          env LANG=C XDG_CACHE_HOME=/tmp XDG_DATA_DIRS=/custom/share \
            bash -lc 'test "$LANG" = C && test "$XDG_CACHE_HOME" = /tmp && test "$XDG_DATA_DIRS" = /custom/share'
          env LANG= bash -ic 'test -z "$LANG"'
        '';
      }
    ];
  };
}
