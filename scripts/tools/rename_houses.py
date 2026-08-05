import re
from collections import defaultdict

FILE = r"scenes\building_blocks\neighborhood.tscn"

with open(FILE, "r", encoding="utf-8") as f:
    lines = f.readlines()

# Step 1: Find all house nodes and their positions
houses = []  # list of (line_idx, old_name, parent_path, x, z)

for i, line in enumerate(lines):
    m = re.match(r'\[node name="(house v1_\d+)" parent="([^"]+)"', line)
    if not m:
        continue
    if i + 1 >= len(lines):
        continue
    tline = lines[i + 1]
    tm = re.search(
        r'Transform3D\([^)]+,\s*([-\d.e]+),\s*([-\d.e]+),\s*([-\d.e]+)\)',
        tline.strip(),
    )
    if not tm:
        continue
    x = float(tm.group(1))
    z = float(tm.group(3))
    old_name = m.group(1)
    parent_path = m.group(2)
    houses.append((i, old_name, parent_path, x, z))

print(f"Found {len(houses)} houses")

# Step 2: Group by X row (round to nearest 5)
row_groups = defaultdict(list)
for idx, name, parent, x, z in houses:
    x_rounded = round(x / 5) * 5
    row_groups[x_rounded].append((idx, name, parent, x, z))

# Step 3: Sort rows by X ascending (most negative = row 1)
sorted_x = sorted(row_groups.keys())
row_map = {}
for row_num, x_val in enumerate(sorted_x, 1):
    row_map[x_val] = row_num

# Step 4: Within each row, sort by Z ascending (most negative = house 1)
renames = []  # list of (line_idx, old_name, parent_path, new_name)

for x_val in sorted_x:
    row_num = row_map[x_val]
    row_houses = sorted(row_groups[x_val], key=lambda h: h[4])
    for house_num, (idx, name, parent, hx, hz) in enumerate(
        row_houses, 1
    ):
        new_name = f"house_row{row_num}_house{house_num}"
        renames.append((idx, name, parent, new_name))

print(f"Rows: {len(sorted_x)}")
for x_val in sorted_x:
    row_num = row_map[x_val]
    count = len(row_groups[x_val])
    print(f"  Row {row_num}: x={x_val}, {count} houses")

# Step 5: Build replacement maps
line_renames = {}  # line_idx -> (old_name, new_name)
path_renames = {}  # (parent_path, old_name) -> new_name

for idx, old_name, parent_path, new_name in renames:
    line_renames[idx] = (old_name, new_name)
    path_renames[(parent_path, old_name)] = new_name

# Step 6: Replace in file
new_lines = []
for i, line in enumerate(lines):
    # Replace node name declarations (exact line match)
    if i in line_renames:
        old, new = line_renames[i]
        line = line.replace(f'"{old}"', f'"{new}"')

    # Replace parent path references for child nodes
    m = re.match(r'\[node name="([^"]+)" parent="([^"]+)"', line)
    if m:
        parent_ref = m.group(2)
        parts = parent_ref.split("/")
        if len(parts) >= 2:
            potential_old = parts[-1]
            potential_path = "/".join(parts[:-1])
            key = (potential_path, potential_old)
            if key in path_renames:
                new_parent = (
                    "/".join(parts[:-1])
                    + "/"
                    + path_renames[key]
                )
                line = line.replace(
                    f'parent="{parent_ref}"',
                    f'parent="{new_parent}"',
                )

    new_lines.append(line)

with open(FILE, "w", encoding="utf-8") as f:
    f.writelines(new_lines)

print(f"\nRenamed {len(renames)} houses")
print("Done!")
