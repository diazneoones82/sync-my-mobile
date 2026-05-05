# Publish To GitHub

Suggested GitHub location:

```text
Neo Apps / Sync My Mobile
```

Suggested repository name:

```text
sync-my-mobile
```

Suggested description:

```text
Open-source LAN sync apps for downloading selected Android, iPhone, and cloud files to a Windows desktop.
```

## Publish With GitHub CLI

Install Git and GitHub CLI, then sign in:

```powershell
gh auth login
```

Then run the included publish script from the project root:

```powershell
.\publish-github.ps1
```

To publish under an organization or account explicitly:

```powershell
.\publish-github.ps1 -Owner "YOUR_GITHUB_OWNER_OR_ORG" -Repo "sync-my-mobile"
```

Manual commands:

```powershell
git init
git add .
git commit -m "Open source Sync My Mobile"
gh repo create sync-my-mobile --public --source . --remote origin --push --description "Open-source LAN sync apps for downloading selected Android, iPhone, and cloud files to a Windows desktop."
```

Create a release and upload final builds:

```powershell
gh release create v1.0.0 "dist\Sync My Mobile Desktop.exe" "dist\Sync My Mobile Android.apk" --title "Sync My Mobile v1.0.0" --notes "Initial open-source release by Neo Apps."
```

## Publisher Note

The Windows EXE metadata says `Neo Apps`, but Windows Verified Publisher requires Authenticode signing with a trusted code-signing certificate.
