# RDP Punctuation Test

## Test Strings for Manual Verification

Open a text editor in your RDP session and dictate these phrases to verify punctuation works correctly:

### Basic Punctuation
```
Hello, world!
```
Expected: `Hello, world!`
Should see: comma after Hello, exclamation at end

### Question Marks
```
How are you? I'm doing great.
```
Expected: `How are you? I'm doing great.`
Should see: question mark after "you", apostrophe in "I'm", period at end

### Quotes and Apostrophes  
```
She said, "It's working perfectly!"
```
Expected: `She said, "It's working perfectly!"`
Should see: comma, opening quote, apostrophe in "It's", closing quote, exclamation

### Periods and Commas
```
First, second, third. Done.
```
Expected: `First, second, third. Done.`
Should see: commas between words, periods at end of sentences

### Slash vs Period (the reported bug)
```
The path is /usr/local/bin. The file is readme.txt.
```
Expected: `The path is /usr/local/bin. The file is readme.txt.`
Should see: forward slashes in path, periods after sentences and in filename

### Mixed Punctuation
```
Cost: $42.99 (plus tax). Email: user@example.com
```
Expected: `Cost: $42.99 (plus tax). Email: user@example.com`
Should see: colon, dollar sign, period in decimal, parentheses, period, colon, at sign

### All Punctuation Characters
```
. , ! ? ; : ' " - _ ( ) [ ] { } / \ | @ # $ % ^ & * + = ` ~
```
This tests every punctuation key. Each should appear correctly, NOT as a slash.

## Diagnostic Test Results

From `KeyCodeDiagnosticTests`:
- Period (`.`) uses keyCode 47 (correct)
- Slash (`/`) uses keyCode 44 (correct)  
- These are different keys, so periods should NEVER become slashes

## Recent Changes

**v0.2.4 with RDP punctuation fix:**
1. Added 1ms delays between Shift and character events
2. Added delays between key down/up events
3. Ensures RDP has time to process each keystroke correctly

## If Problems Persist

If punctuation still becomes slashes:
1. Check that "Auto-switch typing for remote sessions (RDP/VM)" is enabled in Settings
2. Verify the app detected your RDP client (check Diagnostics → Last Run Info)
3. Try toggling the setting off and back on
4. Try dictating directly (not RDP) to confirm local typing works
5. Report which specific punctuation marks fail (we'll add more delays if needed)
