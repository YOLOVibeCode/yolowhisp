# YOLOWhisp Model Accuracy Benchmark

Samples: 10

Ranked by mean Semantic WER (number-normalized; lower is better), tie-broken by punctuation F1.

| Rank | Model | Prompt | Sem Acc | Word Acc | Sem WER | WER | CER | Punct F1 | Speed (xRT) |
|------|-------|--------|---------|----------|---------|-----|-----|----------|-------------|
| 1 | large-v3-turbo | punct-prompt | 98.8% | 97.6% | 1.2% | 2.4% | 2.9% | 0.86 | 0.36x |
| 2 | small | punct-prompt | 97.8% | 95.6% | 2.2% | 4.4% | 4.8% | 0.86 | 0.20x |
| 3 | base | no-prompt | 96.9% | 96.9% | 3.1% | 3.1% | 2.8% | 0.80 | 0.19x |
| 4 | small | no-prompt | 96.9% | 94.7% | 3.1% | 5.3% | 4.6% | 0.80 | 0.19x |
| 5 | large-v3-turbo | no-prompt | 96.9% | 96.9% | 3.1% | 3.1% | 2.8% | 0.79 | 0.38x |
| 6 | base | punct-prompt | 90.3% | 90.3% | 9.7% | 9.7% | 9.1% | 0.81 | 0.19x |

Best (raw): **large-v3-turbo** (punct-prompt) — 98.8% semantic accuracy, punctuation F1 0.86.

## AI Polish (final stage)

Raw transcription vs. the same text after AI Polish. Δ uses Semantic WER (positive = polish helped).

| Model | Prompt | Raw Sem WER | Polished Sem WER | Δ Sem WER | Raw Punct F1 | Polished Punct F1 |
|-------|--------|-------------|------------------|-----------|--------------|-------------------|
| large-v3-turbo | punct-prompt | 1.2% | 2.5% | -1.2% | 0.86 | 0.83 |
| small | punct-prompt | 2.2% | 6.1% | -4.0% | 0.86 | 0.86 |
| base | no-prompt | 3.1% | 7.0% | -4.0% | 0.80 | 0.79 |
| small | no-prompt | 3.1% | 7.0% | -4.0% | 0.80 | 0.78 |
| large-v3-turbo | no-prompt | 3.1% | 7.0% | -4.0% | 0.79 | 0.79 |
| base | punct-prompt | 9.7% | 13.6% | -4.0% | 0.81 | 0.79 |

Best (after polish): **large-v3-turbo** (punct-prompt) — 97.5% semantic accuracy.

## Per-sample transcriptions

### base / no-prompt

- `samples/ref_01.aiff` (WER 0%)
  - ref: Hello, how are you? I'm doing great today!
  - hyp: Hello, how are you? I'm doing great today.
  - polished: Hello, how are you? I'm doing great today. (WER 0%)
- `samples/ref_02.aiff` (WER 18%)
  - ref: Let's meet at 3:30 PM on Tuesday, the 28th.
  - hyp: Let's meet at 3.30 p.m. on Tuesday, the 28th.
  - polished: Let's meet at 3:30 p.m., on Tuesday, the 28th. (WER 18%)
- `samples/ref_03.aiff` (WER 0%)
  - ref: She bought 12 apples, 3 oranges, and 1 banana.
  - hyp: She bought 12 apples, 3 oranges, and 1 banana.
  - polished: She bought 12 apples, 3 oranges, and 1 banana. (WER 0%)
- `samples/ref_04.aiff` (WER 0%)
  - ref: Don't forget: it's urgent, really urgent!
  - hyp: Don't forget it's urgent, really urgent.
  - polished: Don't forget it's urgent, really urgent. (WER 0%)
- `samples/ref_05.aiff` (WER 12%)
  - ref: What's the difference between affect and effect?
  - hyp: What's the difference between effect and effect?
  - polished: What's the difference between effect and affect? (WER 25%)
- `samples/ref_06.aiff` (WER 0%)
  - ref: The meeting is rescheduled to next week; please confirm.
  - hyp: The meeting is rescheduled to next week, please confirm.
  - polished: The meeting is rescheduled to next week, please confirm. (WER 0%)
- `samples/ref_07.aiff` (WER 0%)
  - ref: Wow, that's amazing... isn't it incredible?
  - hyp: Wow, that's amazing, isn't it incredible?
  - polished: Wow, that's amazing, isn't it? Incredible? (WER 0%)
- `samples/ref_08.aiff` (WER 0%)
  - ref: Our revenue grew 25% year over year, reaching $4.2 million.
  - hyp: Our revenue grew 25% year over year, reaching $4.2 million.
  - polished: Our revenue grew 25% year over year, reaching $4.2 million. (WER 0%)
- `samples/ref_09.aiff` (WER 0%)
  - ref: Dr. Smith said the results were, quote, very promising, end quote.
  - hyp: Dr. Smith said the results were, quote, "very promising," end quote.
  - polished: Dr. Smith said the results were, "very promising." (WER 27%)
- `samples/ref_10.aiff` (WER 0%)
  - ref: Can you send me the report by Friday at noon?
  - hyp: Can you send me the report by Friday at noon?
  - polished: Can you send me the report by Friday at noon? (WER 0%)

### base / punct-prompt

- `samples/ref_01.aiff` (WER 0%)
  - ref: Hello, how are you? I'm doing great today!
  - hyp: Hello, how are you? I'm doing great today.
  - polished: Hello, how are you? I'm doing great today. (WER 0%)
- `samples/ref_02.aiff` (WER 9%)
  - ref: Let's meet at 3:30 PM on Tuesday, the 28th.
  - hyp: Let's meet at 3:30 PM on Tuesday, 28th.
  - polished: Let's meet at 3:30 PM on Tuesday, 28th. (WER 9%)
- `samples/ref_03.aiff` (WER 0%)
  - ref: She bought 12 apples, 3 oranges, and 1 banana.
  - hyp: She bought 12 apples, 3 oranges, and 1 banana.
  - polished: She bought 12 apples, 3 oranges, and 1 banana. (WER 0%)
- `samples/ref_04.aiff` (WER 75%)
  - ref: Don't forget: it's urgent, really urgent!
  - hyp: Really urgent!
  - polished: Really urgent! (WER 75%)
- `samples/ref_05.aiff` (WER 12%)
  - ref: What's the difference between affect and effect?
  - hyp: What's the difference between effect and effect?
  - polished: What's the difference between effect and affect? (WER 25%)
- `samples/ref_06.aiff` (WER 0%)
  - ref: The meeting is rescheduled to next week; please confirm.
  - hyp: The meeting is rescheduled to next week, please confirm.
  - polished: The meeting is rescheduled to next week. Please confirm. (WER 0%)
- `samples/ref_07.aiff` (WER 0%)
  - ref: Wow, that's amazing... isn't it incredible?
  - hyp: Wow, that's amazing! Isn't it incredible?
  - polished: Wow, that's amazing! Isn't it incredible? (WER 0%)
- `samples/ref_08.aiff` (WER 0%)
  - ref: Our revenue grew 25% year over year, reaching $4.2 million.
  - hyp: Our revenue grew 25% year over year, reaching $4.2 million.
  - polished: Our revenue grew 25% year over year, reaching $4.2 million. (WER 0%)
- `samples/ref_09.aiff` (WER 0%)
  - ref: Dr. Smith said the results were, quote, very promising, end quote.
  - hyp: Dr. Smith said the results were, quote, "very promising," end quote.
  - polished: Dr. Smith said the results were, "very promising." (WER 27%)
- `samples/ref_10.aiff` (WER 0%)
  - ref: Can you send me the report by Friday at noon?
  - hyp: Can you send me the report by Friday at noon?
  - polished: Can you send me the report by Friday at noon? (WER 0%)

### large-v3-turbo / no-prompt

- `samples/ref_01.aiff` (WER 0%)
  - ref: Hello, how are you? I'm doing great today!
  - hyp: Hello, how are you? I'm doing great today.
  - polished: Hello, how are you? I'm doing great today. (WER 0%)
- `samples/ref_02.aiff` (WER 18%)
  - ref: Let's meet at 3:30 PM on Tuesday, the 28th.
  - hyp: Let's meet at 3.30 p.m. on Tuesday, the 28th.
  - polished: Let's meet at 3:30 p.m. on Tuesday, the 28th. (WER 18%)
- `samples/ref_03.aiff` (WER 0%)
  - ref: She bought 12 apples, 3 oranges, and 1 banana.
  - hyp: She bought 12 apples, 3 oranges, and 1 banana.
  - polished: She bought 12 apples, 3 oranges, and 1 banana. (WER 0%)
- `samples/ref_04.aiff` (WER 0%)
  - ref: Don't forget: it's urgent, really urgent!
  - hyp: Don't forget, it's urgent, really urgent.
  - polished: Don't forget, it's urgent, really urgent. (WER 0%)
- `samples/ref_05.aiff` (WER 12%)
  - ref: What's the difference between affect and effect?
  - hyp: What's the difference between effect and effect?
  - polished: What's the difference between effect and affect? (WER 25%)
- `samples/ref_06.aiff` (WER 0%)
  - ref: The meeting is rescheduled to next week; please confirm.
  - hyp: The meeting is rescheduled to next week, please confirm.
  - polished: The meeting is rescheduled to next week, please confirm. (WER 0%)
- `samples/ref_07.aiff` (WER 0%)
  - ref: Wow, that's amazing... isn't it incredible?
  - hyp: Wow, that's amazing, isn't it incredible?
  - polished: Wow, that's amazing. Isn't it incredible? (WER 0%)
- `samples/ref_08.aiff` (WER 0%)
  - ref: Our revenue grew 25% year over year, reaching $4.2 million.
  - hyp: Our revenue grew 25% year-over-year, reaching $4.2 million.
  - polished: Our revenue grew 25% year over year, reaching $4.2 million. (WER 0%)
- `samples/ref_09.aiff` (WER 0%)
  - ref: Dr. Smith said the results were, quote, very promising, end quote.
  - hyp: Dr. Smith said the results were, quote, very promising, end quote.
  - polished: Dr. Smith said the results were "very promising." (WER 27%)
- `samples/ref_10.aiff` (WER 0%)
  - ref: Can you send me the report by Friday at noon?
  - hyp: Can you send me the report by Friday at noon?
  - polished: Can you send me the report by Friday at noon? (WER 0%)

### large-v3-turbo / punct-prompt

- `samples/ref_01.aiff` (WER 0%)
  - ref: Hello, how are you? I'm doing great today!
  - hyp: Hello, how are you? I'm doing great today!
  - polished: Hello, how are you? I'm doing great today! (WER 0%)
- `samples/ref_02.aiff` (WER 0%)
  - ref: Let's meet at 3:30 PM on Tuesday, the 28th.
  - hyp: Let's meet at 3:30 PM on Tuesday, the 28th.
  - polished: Let's meet at 3:30 PM on Tuesday, the 28th. (WER 0%)
- `samples/ref_03.aiff` (WER 11%)
  - ref: She bought 12 apples, 3 oranges, and 1 banana.
  - hyp: She bought 12 apples, 3 oranges, and one banana.
  - polished: She bought 12 apples 3 oranges and one banana. (WER 11%)
- `samples/ref_04.aiff` (WER 0%)
  - ref: Don't forget: it's urgent, really urgent!
  - hyp: Don't forget — it's urgent, really urgent!
  - polished: Don't forget—it's urgent, really urgent! (WER 0%)
- `samples/ref_05.aiff` (WER 12%)
  - ref: What's the difference between affect and effect?
  - hyp: What's the difference between effect and effect?
  - polished: What's the difference between effect and affect? (WER 25%)
- `samples/ref_06.aiff` (WER 0%)
  - ref: The meeting is rescheduled to next week; please confirm.
  - hyp: The meeting is rescheduled to next week, please confirm.
  - polished: The meeting is rescheduled to next week. Please confirm. (WER 0%)
- `samples/ref_07.aiff` (WER 0%)
  - ref: Wow, that's amazing... isn't it incredible?
  - hyp: Wow, that's amazing, isn't it incredible?
  - polished: Wow, that's amazing, isn't it? Incredible. (WER 0%)
- `samples/ref_08.aiff` (WER 0%)
  - ref: Our revenue grew 25% year over year, reaching $4.2 million.
  - hyp: Our revenue grew 25% year-over-year, reaching $4.2 million.
  - polished: Our revenue grew 25% year over year, reaching $4.2 million. (WER 0%)
- `samples/ref_09.aiff` (WER 0%)
  - ref: Dr. Smith said the results were, quote, very promising, end quote.
  - hyp: Dr. Smith said the results were, quote, "very promising," end quote.
  - polished: Dr. Smith said the results were, quote, "very promising," end-quote. (WER 0%)
- `samples/ref_10.aiff` (WER 0%)
  - ref: Can you send me the report by Friday at noon?
  - hyp: Can you send me the report by Friday at noon?
  - polished: Can you send me the report by Friday at noon? (WER 0%)

### small / no-prompt

- `samples/ref_01.aiff` (WER 0%)
  - ref: Hello, how are you? I'm doing great today!
  - hyp: Hello, how are you? I'm doing great today.
  - polished: Hello, how are you? I'm doing great today. (WER 0%)
- `samples/ref_02.aiff` (WER 18%)
  - ref: Let's meet at 3:30 PM on Tuesday, the 28th.
  - hyp: Let's meet at 3.30 p.m. on Tuesday, the 28th.
  - polished: Let's meet at 3:30 p.m. on Tuesday, the 28th. (WER 18%)
- `samples/ref_03.aiff` (WER 22%)
  - ref: She bought 12 apples, 3 oranges, and 1 banana.
  - hyp: She bought 12 apples, three oranges, and one banana.
  - polished: She bought 12 apples, three oranges, and one banana. (WER 22%)
- `samples/ref_04.aiff` (WER 0%)
  - ref: Don't forget: it's urgent, really urgent!
  - hyp: Don't forget, it's urgent, really urgent.
  - polished: Don't forget, it's urgent, really urgent. (WER 0%)
- `samples/ref_05.aiff` (WER 12%)
  - ref: What's the difference between affect and effect?
  - hyp: What's the difference between effect and effect?
  - polished: What's the difference between effect and affect? (WER 25%)
- `samples/ref_06.aiff` (WER 0%)
  - ref: The meeting is rescheduled to next week; please confirm.
  - hyp: The meeting is rescheduled to next week, please confirm.
  - polished: The meeting is rescheduled to next week. Please confirm. (WER 0%)
- `samples/ref_07.aiff` (WER 0%)
  - ref: Wow, that's amazing... isn't it incredible?
  - hyp: Wow, that's amazing, isn't it incredible?
  - polished: Wow, that's amazing; isn't it incredible? (WER 0%)
- `samples/ref_08.aiff` (WER 0%)
  - ref: Our revenue grew 25% year over year, reaching $4.2 million.
  - hyp: Our revenue grew 25% year over year, reaching $4.2 million.
  - polished: Our revenue grew 25% year over year, reaching $4.2 million. (WER 0%)
- `samples/ref_09.aiff` (WER 0%)
  - ref: Dr. Smith said the results were, quote, very promising, end quote.
  - hyp: Dr. Smith said the results were, quote, "very promising," end quote.
  - polished: Dr. Smith said the results were "very promising." (WER 27%)
- `samples/ref_10.aiff` (WER 0%)
  - ref: Can you send me the report by Friday at noon?
  - hyp: Can you send me the report by Friday at noon?
  - polished: Can you send me the report by Friday at noon? (WER 0%)

### small / punct-prompt

- `samples/ref_01.aiff` (WER 0%)
  - ref: Hello, how are you? I'm doing great today!
  - hyp: Hello, how are you? I'm doing great today!
  - polished: Hello, how are you? I'm doing great today! (WER 0%)
- `samples/ref_02.aiff` (WER 9%)
  - ref: Let's meet at 3:30 PM on Tuesday, the 28th.
  - hyp: Let's meet at 3.30 PM on Tuesday, 28th.
  - polished: Let's meet at 3:30 PM on Tuesday, 28th. (WER 9%)
- `samples/ref_03.aiff` (WER 22%)
  - ref: She bought 12 apples, 3 oranges, and 1 banana.
  - hyp: She bought 12 apples, three oranges, and one banana.
  - polished: She bought 12 apples, three oranges, and one banana. (WER 22%)
- `samples/ref_04.aiff` (WER 0%)
  - ref: Don't forget: it's urgent, really urgent!
  - hyp: Don't forget — it's urgent, really urgent!
  - polished: Don't forget—it's urgent, really urgent! (WER 0%)
- `samples/ref_05.aiff` (WER 12%)
  - ref: What's the difference between affect and effect?
  - hyp: What's the difference between effect and effect?
  - polished: What's the difference between effect and affect? (WER 25%)
- `samples/ref_06.aiff` (WER 0%)
  - ref: The meeting is rescheduled to next week; please confirm.
  - hyp: The meeting is rescheduled to next week, please confirm.
  - polished: The meeting is rescheduled to next week. Please confirm. (WER 0%)
- `samples/ref_07.aiff` (WER 0%)
  - ref: Wow, that's amazing... isn't it incredible?
  - hyp: Wow, that's amazing! Isn't it incredible?
  - polished: Wow, that's amazing! Isn't it incredible? (WER 0%)
- `samples/ref_08.aiff` (WER 0%)
  - ref: Our revenue grew 25% year over year, reaching $4.2 million.
  - hyp: Our revenue grew 25% year over year, reaching $4.2 million.
  - polished: Our revenue grew 25% year over year, reaching $4.2 million. (WER 0%)
- `samples/ref_09.aiff` (WER 0%)
  - ref: Dr. Smith said the results were, quote, very promising, end quote.
  - hyp: Dr. Smith said the results were, quote, "very promising," end quote.
  - polished: Dr. Smith said the results were, "very promising." (WER 27%)
- `samples/ref_10.aiff` (WER 0%)
  - ref: Can you send me the report by Friday at noon?
  - hyp: Can you send me the report by Friday at noon?
  - polished: Can you send me the report by Friday at noon? (WER 0%)
