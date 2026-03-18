import os

seeds_dir = "seeds"
os.makedirs(seeds_dir, exist_ok=True)

# def make_seed(name, pattern, subject=b"test"):
#     length = len(pattern)
#     length_bytes = length.to_bytes(2, byteorder='little')
#     with open(os.path.join(seeds_dir, name), "wb") as f:
#         f.write(length_bytes + pattern + subject)

verbs = [b"(*ACCEPT)", b"(*FAIL)", b"(*COMMIT)", b"(*SKIP)", b"(*PRUNE)", b"(*THEN)"]

for verb in verbs:
    verb_name = verb.decode().strip("(*)").lower()
    for depth in [1,5,10,25,40,50]:
        pattern = b"(" * depth + verb + b")" * depth
        len_bytes = len(pattern).to_bytes(2, 'little')
        with open(os.path.join(seeds_dir, f"{verb_name}_{depth}"), "wb") as f:
            f.write(len_bytes + pattern + b"test")

for count in [50, 150, 300, 500, 1000]:
    pattern = b"(a)" * count
    len_bytes = len(pattern).to_bytes(2, 'little')
    with open(os.path.join(seeds_dir, f"groups_{count}"), "wb") as f:
            f.write(len_bytes + pattern + b"a" * min(count, 200))
    #make_seed(f"groups_{count}", pattern, subject=b"a" * min(count, 200))

# Nested capturing groups
for count in [50, 150, 300]:
    pattern = b"((a)(b))" * (count // 2)
    len_bytes = len(pattern).to_bytes(2, 'little')
    with open(os.path.join(seeds_dir, f"groups_nest_{count}"), "wb") as f:
            f.write(len_bytes + pattern + b"ab" * min(count, 100))
    #make_seed(f"groups_nested_{count}", pattern, subject=b"ab" * min(count, 100))

# Deeply nested capturing groups
for depth in [10, 25, 50]:
    pattern = b"(" * depth + b"a" + b")" * depth
    len_bytes = len(pattern).to_bytes(2, 'little')
    with open(os.path.join(seeds_dir, f"deep_nest_{depth}"), "wb") as f:
            f.write(len_bytes + pattern + b"a")
    #make_seed(f"groups_deep_{depth}", pattern, subject=b"a")

# Deep nesting wrapping many flat groups
for depth in [10, 20, 30]:
    for count in [50, 150, 300]:
        inner = b"(a)" * count
        pattern = b"(" * depth + inner + b")" * depth
        len_bytes = len(pattern).to_bytes(2, 'little')
        with open(os.path.join(seeds_dir, f"deep_nest_double_{depth}_{count}"), "wb") as f:
                f.write(len_bytes + pattern + b"a" * min(count, 200))
        #make_seed(f"groups_deep_{depth}_flat_{count}", pattern, subject=b"a" * min(count, 200))