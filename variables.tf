variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}

variable "targets" {
  type        = list(string)
  description = "URLs to scan, each with a report of its own. Required, with no default: list only sites you're allowed to scan."

  validation {
    condition     = length(var.targets) > 0 && alltrue([for t in var.targets : can(regex("^https?://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~/%?=&+,;-]*)?$", t))])
    error_message = "targets is a list of one or more http or https URLs, such as \"https://staging.example.com/\". Credentials in the URL and IPv6 addresses aren't accepted."
  }

  # Reports are named for their URLs with everything but letters and digits
  # as _, so two URLs mustn't meet.
  validation {
    condition     = length(distinct([for t in var.targets : trim(replace(t, "/[^A-Za-z0-9]+/", "_"), "_")])) == length(var.targets)
    error_message = "Two of targets would write to the same report. URLs that differ only in punctuation can't be told apart."
  }
}

variable "active_scan" {
  type        = bool
  default     = false
  description = "Attack every target with zap-full-scan.py instead of the passive zap-baseline.py. It sends real attacks that can change data or take a site down. Only for sites you own or have written permission to attack."
}

variable "zap_version" {
  type        = string
  default     = "2.17.0"
  description = "Tag of the ghcr.io/zaproxy/zaproxy image. Change image_digest with it."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.zap_version))
    error_message = "zap_version is a release number such as \"2.17.0\"."
  }
}

variable "image_digest" {
  type        = string
  default     = "sha256:030d3df57735dacbb83464854758e674dd9ad01d79d12a129a8e58b1fd384238"
  description = "Digest of ghcr.io/zaproxy/zaproxy for zap_version. ZAP rebuilds the same tag often, so the digest is what fixes what runs."

  validation {
    condition     = can(regex("^sha256:[a-f0-9]{64}$", var.image_digest))
    error_message = "image_digest must be \"sha256:\" followed by 64 hex digits."
  }
}

variable "update_addons" {
  type        = bool
  default     = false
  description = "Let ZAP fetch its newest add-ons and beta rules as each scan starts. It finds more, but runs code the image digest doesn't pin."
}

variable "spider_minutes" {
  type        = number
  default     = 1
  description = "Longest the spider walks each target, in minutes."

  validation {
    condition     = var.spider_minutes >= 1 && floor(var.spider_minutes) == var.spider_minutes
    error_message = "spider_minutes must be a whole number, 1 or more."
  }
}

variable "max_scan_minutes" {
  type        = number
  default     = 120
  description = "Longest one target's scan may take, in minutes. A scan that runs out of time counts as failed. Raise it for active scans of large sites."

  validation {
    condition     = var.max_scan_minutes >= 1 && floor(var.max_scan_minutes) == var.max_scan_minutes
    error_message = "max_scan_minutes must be a whole number, 1 or more."
  }
}

variable "schedule" {
  type        = string
  default     = "weekly"
  description = "When the scan timer runs, as a systemd OnCalendar expression such as \"weekly\" or \"Sun 03:00\"."

  validation {
    condition     = !strcontains(var.schedule, "\n") && !strcontains(var.schedule, "'")
    error_message = "schedule is a single-line systemd calendar expression."
  }
}

variable "keep" {
  type        = number
  default     = 8
  description = "Number of scans to keep under /var/lib/conn3x-zap. Older ones are deleted after each scan."

  validation {
    condition     = var.keep >= 1 && floor(var.keep) == var.keep
    error_message = "keep must be a whole number, 1 or more."
  }
}

variable "run_now" {
  type        = bool
  default     = false
  description = "Scan during the apply: on the first apply, and again whenever the scan's settings change."
}
