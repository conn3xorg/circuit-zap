locals {
  image       = "ghcr.io/zaproxy/zaproxy:${var.zap_version}@${var.image_digest}"
  results_dir = "/var/lib/conn3x-zap"
  script      = "/usr/local/sbin/conn3x-zap"
  unit        = "conn3x-zap"

  # zap-baseline.py spiders the target and only reads what comes back.
  # zap-full-scan.py attacks it, so it runs only when active_scan asks.
  scan = var.active_scan ? "zap-full-scan.py" : "zap-baseline.py"

  # -silent stops ZAP fetching newer add-ons as it starts, so the digest alone
  # decides what runs. The scripts' own check for it is this option's text.
  silent = var.update_addons ? "" : "-z -silent"

  # Each report is named for its URL.
  reports = { for t in var.targets : t => trim(replace(t, "/[^A-Za-z0-9]+/", "_"), "_") }

  run_script = <<-EOT
    #!/bin/sh
    # Written by Conn3x. Changes here are overwritten on the next apply.
    # Runs ${local.scan} against the listed targets, and nothing else, and
    # writes the reports to a new directory under ${local.results_dir}. Every
    # target gets its turn. latest moves only if they all gave a report.
    set -u
    umask 077
    dir=${local.results_dir}
    run=$(date -u +%Y%m%dT%H%M%SZ)
    mkdir -p "$dir/$run"
    # ZAP runs as uid 1000 in its image. The 0700 parent keeps everyone else out.
    chown 1000:1000 "$dir/$run"
    failed=0
    scan() {
      # Podman's own network with no published ports, never the host's: these
      # scripts start ZAP's API on all addresses with its key turned off.
      # On Ubuntu 24.04, Podman's AppArmor profile stops ZAP's wrapper signalling
      # Xvfb when a scan ends, and the container then never exits. --timeout
      # is what ends any scan that hangs.
      podman run --rm --name "conn3x-zap-$2" --timeout ${var.max_scan_minutes * 60} \
        --cap-drop=all --security-opt=no-new-privileges --security-opt=apparmor=unconfined \
        -v "$dir/$run:/zap/wrk:rw,Z" \
        ${local.image} \
        ${local.scan} -t "$1" -m ${var.spider_minutes} ${local.silent} \
        -J "$2.json" -r "$2.html" -w "$2.md" >> "$dir/$run/$2.log" 2>&1
      # 0 is clean, and 1 and 2 mean it found something. 3 is a failed scan.
      rc=$?
      if [ "$rc" -gt 2 ] || [ ! -s "$dir/$run/$2.json" ]; then
        echo "The scan of $1 failed with exit code $rc." >&2
        tail -n 20 "$dir/$run/$2.log" >&2
        failed=1
      fi
    }
    %{for t, r in local.reports~}
    scan '${t}' ${r}
    %{endfor~}
    [ "$failed" = 0 ] || exit 1
    # "riskdesc" appears once per kind of alert in each JSON report.
    cat "$dir/$run"/*.json | sed -n 's/.*"riskdesc": *"\([A-Za-z]*\) .*/\1/p' | sort | uniq -c | awk '{ print $2, $1 }' > "$dir/$run/summary.txt"
    ln -sfn "$run" "$dir/latest"
    find "$dir" -mindepth 1 -maxdepth 1 -type d -name '2*' | sort | head -n -${var.keep} | xargs -r rm -rf
    cat "$dir/$run/summary.txt"
  EOT
}

circuit "zap" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "podman" {
    package {
      name = "podman"
    }
  }

  # Pulled here so a bad digest fails the apply, not a scan next week.
  step "image" {
    command {
      command = "podman pull ${local.image}"
      unless  = "podman image exists ${local.image}"
    }
  }

  # Reports describe weaknesses in your sites, so only root reads them.
  step "results_dir" {
    directory {
      path = local.results_dir
      mode = "0700"
    }
  }

  step "script" {
    file {
      path    = local.script
      content = local.run_script
      mode    = "0700"
    }
  }

  step "schedule_valid" {
    command {
      command = "echo 'schedule is not a calendar expression systemd understands: ${var.schedule}' >&2; exit 1"
      unless  = "systemd-analyze calendar '${var.schedule}' >/dev/null"
    }
  }

  step "timer" {
    timer {
      name        = local.unit
      description = "ZAP scan of the listed targets"
      on_calendar = var.schedule
      command     = local.script
      persistent  = true
    }
  }

  step "scan" {
    for_each = toset(var.run_now ? ["scan"] : [])
    command {
      command  = "systemctl start ${local.unit}.service"
      triggers = { script = conn3x_file.zap__script[each.key].revision }
    }
  }
}
