output "results_dir" {
  description = "Directory on each host that holds one directory per scan, newest linked as latest."
  value       = local.results_dir
}

output "summary" {
  description = "Count of alerts by risk from the latest scan on each host. The reports are beside it."
  value       = "${local.results_dir}/latest/summary.txt"
}

output "reports" {
  description = "JSON report of the latest scan for each target. Each has an .html and an .md of the same name."
  value       = { for t, n in local.reports : t => "${local.results_dir}/latest/${n}.json" }
}
