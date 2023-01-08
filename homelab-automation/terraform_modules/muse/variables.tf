variable DISCORD_CLIENT_ID {
  type    = string
  default   = ""
  description = "Client ID used to authenticate with Discord"
}

variable DISCORD_TOKEN {
  type    = string
  default   = ""
  description = "Token used to authenticate with Discord"
}

variable SPOTIFY_CLIENT_ID {
  type    = string
  default   = ""
  description = "Client ID used to authenticate with Spotify"
}

variable SPOTIFY_CLIENT_SECRET {
  type    = string
  default   = ""
  description = "Client secret used to authenticate with Spotify"
}

variable YOUTUBE_API_KEY {
  type    = string
  default   = ""
  description = "The API key used to authenticate with YouTUbe"
}

variable namespace{
  type    = string
  default   = ""
  description = "The name of the namespace to bring up this deployment in."
}