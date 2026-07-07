# Test Fixtures

Drop **5 photos of real book pages** here (iPhone photos are ideal — that's what the app will see). Per PROJECT_PLAN.md §7, vary the conditions:

1. Flat page, good light (baseline)
2. Curved page near the spine
3. Glossy paper with glare
4. Dim / warm indoor light
5. Small print or dialogue-heavy page

Then run the spike from the repo root:

```sh
swift Tools/OCRSpike/main.swift fr-FR Fixtures/*.jpg   # use your target language code
```

Check: word accuracy ≥ 95% (§9), sensible sentence boundaries, and per-page time ≤ a few seconds.
