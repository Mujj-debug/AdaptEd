# Fix: Missing Noto Fonts Warning

The console warning "Could not find a set of Noto fonts to display all missing characters" 
is caused by emoji rendering on web. Fix it in 2 steps:

## Step 1 — Download the font
Download NotoColorEmoji.ttf from:
https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf

## Step 2 — Add to your project
Place the file at:
```
your_project/
  fonts/
    NotoColorEmoji.ttf   ← put it here
  lib/
  pubspec.yaml
```

## Step 3 — pubspec.yaml already updated
The pubspec.yaml output already includes the font declaration:
```yaml
flutter:
  uses-material-design: true
  fonts:
    - family: NotoColorEmoji
      fonts:
        - asset: fonts/NotoColorEmoji.ttf
```

## Step 4 — Run
```bash
flutter pub get
flutter run -d chrome
```

The warning will be gone.
