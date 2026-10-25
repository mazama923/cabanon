export function base_url() {
  const is_local_development =
    (window.location.hostname === "localhost" ||
      window.location.hostname === "127.0.0.1") &&
    window.location.port === "1234";

  return is_local_development ? "http://localhost:8080" : "";
}

export function planning_period() {
  const now = new Date();
  const planning_month = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  const month = String(planning_month.getMonth() + 1).padStart(2, "0");

  return `${planning_month.getFullYear()}-${month}`;
}
