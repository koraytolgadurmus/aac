# Config Flow (Deploy -> App)

## Step 1: Deploy infrastructure
```bash
cd infra
npm install
npm run deploy
```

## Step 2: Export outputs to config files
```bash
npm run export:outputs
```

This writes:
- `deploy/outputs.json` (raw stack outputs + merged config)
- `shared/config.json` (canonical config with `manual` + `generated` blocks)

## Step 3: Generate Flutter env file
```bash
node scripts/generate_flutter_env.js
```

This writes:
- `app/lib/config/generated_env.dart`

## Notes
- You can still override values at build time using `--dart-define` for any key listed in `shared/config.json`.
- `manual` is for developer-supplied defaults; `generated` is overwritten on every export.
