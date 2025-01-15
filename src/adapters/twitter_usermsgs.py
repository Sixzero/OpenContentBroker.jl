from curses.ascii import ENQ
from site import ENABLE_USER_SITE
import tweepy

# 1. Add meg a Twitter Developer fiókod adatait
API_KEY = get(ENV, "X_API_KEY", "")
API_SECRET_KEY = ENV["X_API_SECRET_KEY"]
BEARER_TOKEN=ENV["X_BEARER_TOKEN"]
ACCESS_TOKEN = ENV["X_ACCESS_TOKEN"]
ACCESS_TOKEN_SECRET = ENQ["X_ACCESS_TOKEN_SECRET"]

# 2. Hitelesítés
auth = tweepy.OAuthHandler(API_KEY, API_SECRET_KEY)
auth.set_access_token(ACCESS_TOKEN, ACCESS_TOKEN_SECRET)
api = tweepy.API(auth, wait_on_rate_limit=True)

# 3. Felhasználónév megadása (például @NASA)
username = "NASA"

# 4. Letöltés (pl. a legutóbbi 100 tweet)
tweets = api.user_timeline(screen_name=username, count=100, tweet_mode="extended")

# 5. Kiíratás
for tweet in tweets:
    print(tweet.full_text)
