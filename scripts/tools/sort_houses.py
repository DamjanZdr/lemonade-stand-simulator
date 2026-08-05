import re

FILE = r"scenes\building_blocks\neighborhood.tscn"

with open(FILE, "r", encoding="utf-8") as f:
    lines = f.readlines()

# Find all top-level house node blocks and their children
# A house node block starts with [node name="house_rowX_houseY" parent="Houses" or parent="NonPlayableArea/Houses"]
# and includes all subsequent child nodes whose parent path starts with that house's path

# First, identify the two container sections and their line ranges
# We need to find where "Houses" nodes start and end, and where "NonPlayableArea/Houses" start and end

# Strategy: find each house node line, then collect all lines until the next house node
# (or next non-house node at the same or lower level)

house_pattern = re.compile(
    r'\[node name="(house_row\d+_house\d+)" parent="([^"]+)"'
)

# Collect blocks: each block is (sort_key, start_line, end_line, lines_list)
# sort_key = (row_num, house_num)
# We need to identify contiguous blocks of house nodes + their children

# Find all house node positions
house_positions = []  # (line_idx, name, parent, row, house_num)
for i, line in enumerate(lines):
    m = house_pattern.match(line)
    if m:
        name = m.group(1)
        parent = m.group(2)
        # Extract row and house numbers
        nm = re.match(r'house_row(\d+)_house(\d+)', name)
        if nm:
            row = int(nm.group(1))
            hnum = int(nm.group(2))
            house_positions.append((i, name, parent, row, hnum))

print(f"Found {len(house_positions)} house nodes")

# Now we need to group them by their parent container (Houses vs NonPlayableArea/Houses)
# and reorder within each container

# Find the container node lines
containers = {}  # parent_path -> (line_idx, indent_level)
for i, line in enumerate(lines):
    if re.match(r'\[node name="Houses" type="Node3D" parent="([^"]+)"', line):
        m = re.match(r'\[node name="Houses" type="Node3D" parent="([^"]+)"', line)
        containers[m.group(1)] = i
    elif re.match(r'\[node name="Houses" type="Node3D" parent="\."', line):
        containers["."] = i

print(f"Containers: {containers}")

# For each house, find its block (the house node + all child nodes)
# Child nodes have parent paths that start with the house's full path
# Full path = parent + "/" + name

# We need to identify the line range for each house block
# A house block starts at the house node line and ends just before the next house node
# (or before the next non-child node)

# Simple approach: for houses within the same parent, blocks are contiguous
# Let's find blocks by looking at each house and collecting lines until the next
# node that is NOT a child of this house

def get_full_path(parent, name):
    if parent == ".":
        return name
    return f"{parent}/{name}"

# Find all node declarations to understand structure
node_pattern = re.compile(r'\[node name="([^"]+)" parent="([^"]+)"')

# For each house, find its block range
# A house block = house node line + all subsequent lines that are either:
# - child nodes (parent starts with house's full path)
# - blank lines between them
# - metadata/transform lines belonging to those nodes

blocks = []  # list of (sort_key, start_line, end_line, block_lines, parent_container)

for idx, (line_idx, name, parent, row, hnum) in enumerate(house_positions):
    full_path = get_full_path(parent, name)
    # Determine the container (the "Houses" node this belongs to)
    if parent == "Houses":
        container = "Houses"
    elif parent == "NonPlayableArea/Houses":
        container = "NonPlayableArea/Houses"
    else:
        container = parent

    # Find end of block: scan forward until we hit a node whose parent does NOT
    # start with full_path
    end_idx = line_idx + 1
    while end_idx < len(lines):
        nline = lines[end_idx]
        nm = node_pattern.match(nline)
        if nm:
            child_parent = nm.group(2)
            child_name = nm.group(1)
            child_full = get_full_path(child_parent, child_name)
            # Check if this node is a child of our house
            if child_parent.startswith(full_path):
                end_idx += 1
                continue
            else:
                # Not a child - block ends here
                break
        end_idx += 1

    # Don't include trailing blank lines in the block
    block_end = end_idx
    while block_end > line_idx and lines[block_end - 1].strip() == "":
        block_end -= 1

    block_lines = lines[line_idx:block_end]
    # Include one trailing blank line for separation
    if block_end < len(lines) and lines[block_end].strip() == "":
        block_lines.append("\n")

    blocks.append((
        (container, row, hnum),
        line_idx,
        block_end,
        block_lines,
        container,
    ))

# Now we need to find the insertion points for each container
# and replace the house blocks in sorted order

# Group blocks by container
from collections import defaultdict
container_blocks = defaultdict(list)
for sort_key, start, end, blines, container in blocks:
    container_blocks[container].append((sort_key, start, end, blines))

# For each container, sort blocks by (row, house_num)
for container in container_blocks:
    container_blocks[container].sort(key=lambda b: (b[0][1], b[0][2]))

# Now rebuild the file
# Strategy: find the line range that contains all house blocks for each container
# and replace with sorted blocks

# Find min start and max end for each container
container_ranges = {}
for container, cblocks in container_blocks.items():
    min_start = min(b[1] for b in cblocks)
    max_end = max(b[2] for b in cblocks)
    container_ranges[container] = (min_start, max_end)

# Build new file: lines before first container, sorted blocks, lines between containers, etc.
# Sort containers by their start position
sorted_containers = sorted(container_ranges.keys(), key=lambda c: container_ranges[c][0])

new_lines = []
last_pos = 0
for container in sorted_containers:
    min_start, max_end = container_ranges[container]
    # Add lines before this container's house blocks
    new_lines.extend(lines[last_pos:min_start])
    # Add sorted house blocks
    for sort_key, start, end, blines in container_blocks[container]:
        new_lines.extend(blines)
        new_lines.append("\n")  # blank line separator
    last_pos = max_end
    # Skip blank lines between blocks
    while last_pos < len(lines) and lines[last_pos].strip() == "":
        last_pos += 1

# Add remaining lines
new_lines.extend(lines[last_pos:])

with open(FILE, "w", encoding="utf-8") as f:
    f.writelines(new_lines)

print(f"Sorted {len(blocks)} house blocks in {len(sorted_containers)} containers")
print("Done!")
