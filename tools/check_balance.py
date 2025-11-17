import sys
from pathlib import Path
p = Path(r"C:\Users\admin\StudioProjects\HSC_Chat\lib\feature\home\view\chat_screen.dart")
s = p.read_text()
stack = []
pairs = {')':'(', ']':'[', '}':'{'}
line = 1
for i,ch in enumerate(s):
    if ch == '\n':
        line += 1
    if ch in '([{':
        stack.append((ch,line,i))
    elif ch in ')]}':
        if not stack:
            print(f"Unmatched closing {ch} at line {line}")
            sys.exit(1)
        top, tline, idx = stack.pop()
        if pairs[ch] != top:
            print(f"Mismatched {top} opened at line {tline} closed by {ch} at line {line}")
            sys.exit(1)
if stack:
    top, tline, idx = stack[-1]
    print(f"Unclosed {top} opened at line {tline}")
    sys.exit(1)
print('All balanced')

