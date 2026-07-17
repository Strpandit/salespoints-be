Geocoder.configure(
  lookup: :nominatim,
  timeout: 10,
  use_https: true,
  units: :km,
  http_headers: {
    "User-Agent" => "salespoints"
  }
)