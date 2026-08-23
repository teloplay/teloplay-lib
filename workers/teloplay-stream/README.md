# TeloPlay Stream Worker (free)

Browser থেকে public Piped `/streams` CORS/timeout-এ fail করতে পারে। এই Cloudflare Worker প্রথমে Android InnerTube (20.10.38) দিয়ে direct adaptive audio URL resolve করে, তারপর দরকার হলে range-capable audio proxy হিসেবে কাজ করে। Player তোমার Flutter app-এই থাকে (YouTube iframe না)।

## Deploy (Cloudflare free tier)

```bash
cd workers/teloplay-stream
npx wrangler login
npx wrangler deploy
```

Wrangler একটা URL দেবে, যেমন:

```text
https://teloplay-stream.<your-subdomain>.workers.dev
```

`.env`-এ বসাও:

```env
TELOPLAY_STREAM_PROXY_URL=https://teloplay-stream.<your-subdomain>.workers.dev
```

তারপর:

```bash
flutter run -d chrome -t lib/main_web.dart
```

Worker না থাকলে app আগের Piped+CORS path চেষ্টা করবে (এখনো public instance down থাকতে পারে)।
