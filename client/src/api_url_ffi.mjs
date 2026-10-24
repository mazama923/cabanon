export function base_url() {
  const is_local_development =
    (window.location.hostname === "localhost" ||
      window.location.hostname === "127.0.0.1") &&
    window.location.port === "1234";

  return is_local_development ? "http://localhost:8080" : "";
}
