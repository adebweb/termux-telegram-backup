# 🚀 Publish Your Repo to GitHub

## Step 1: Create Repo on GitHub
1. Go to https://github.com/new
2. Name: `termux-telegram-backup`
3. Visibility: **Public** (required for raw links)
4. Check **Add a README** (we will overwrite it)
5. Click **Create repository**

## Step 2: Upload Files
```bash
cd /path/to/termux-telegram-backup

git init
git remote add origin https://github.com/adebweb/termux-telegram-backup.git
git branch -M main

git add .
git commit -m "Initial release v1.0.0"
git push -u origin main
```

## Step 3: Update Raw URLs
Replace `adebweb` in these files with your actual GitHub username:
- `install.sh` → line: `REPO_RAW="https://raw.githubusercontent.com/adebweb/..."`
- `README.md` → all `adebweb` occurrences
- `backup.py` → header comment

## Step 4: Test
```bash
curl -sL https://raw.githubusercontent.com/adebweb/termux-telegram-backup/main/install.sh | bash
```

## ✅ Done!
Your users can now install with one line.
