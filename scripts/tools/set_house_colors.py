import re

FILE = r"scenes\building_blocks\neighborhood.tscn"

with open(FILE, "r", encoding="utf-8") as f:
    lines = f.readlines()

# Pattern: [node name="house_rowX_houseY" ...]
# followed by transform line
# followed by metadata/house_color_index = N

count = 0
for i, line in enumerate(lines):
    m = re.match(r'\[node name="house_row(\d+)_house(\d+)"', line)
    if m:
        house_num = int(m.group(2))
        new_index = (house_num - 1) % 5
        # Find the metadata/house_color_index line within the next few lines
        for j in range(i + 1, min(i + 5, len(lines))):
            if "house_color_index" in lines[j]:
                lines[j] = re.sub(
                    r'house_color_index = \d+',
                    f'house_color_index = {new_index}',
                    lines[j],
                )
                count += 1
                break

with open(FILE, "w", encoding="utf-8") as f:
    f.writelines(lines)

print(f"Updated {count} house color indices")
