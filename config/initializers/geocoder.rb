Geocoder.configure(
  lookup: :google,
  api_key: ENV['GOOGLE_MAPS_API_KEY'],
  timeout: 10,
  use_https: true,
  units: :km,
  params: {
    region: 'in',
    components: 'country:IN'
  },
)