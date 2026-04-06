Import("env")
from pathlib import Path
import re


def _to_str(v):
    if v is None:
        return ""
    return str(v).strip()


def _read_define_values(defines, key):
    values = []
    for d in defines:
        if isinstance(d, tuple) and len(d) >= 2 and _to_str(d[0]) == key:
            values.append(_to_str(d[1]).strip('"').lower())
            continue
        if isinstance(d, str) and d.startswith(f"{key}="):
            values.append(_to_str(d.split("=", 1)[1]).strip('"').lower())
    return values


cpp_defines = env.get("CPPDEFINES", [])
env_name = _to_str(env.get("PIOENV", "")).lower()


def _read_products_from_build_flags():
    try:
        raw = env.GetProjectOption("build_flags", [])
    except Exception:
        raw = []
    if isinstance(raw, str):
        items = [raw]
    else:
        items = [str(x) for x in raw]
    text = " ".join(items)
    matches = re.findall(r"-DDEVICE_PRODUCT=\\\\?\"?([A-Za-z0-9_-]+)", text)
    return [m.lower() for m in matches if m]


products = _read_products_from_build_flags()
if not products:
    products = _read_define_values(cpp_defines, "DEVICE_PRODUCT")
effective_product = products[-1] if products else "aac"


def _read_env_section_text(env_name_value):
    project_dir = Path(env.subst("$PROJECT_DIR"))
    ini_path = project_dir / "platformio.ini"
    if not ini_path.exists():
        return ""
    text = ini_path.read_text(encoding="utf-8")
    start_tag = f"[env:{env_name_value}]"
    start = text.find(start_tag)
    if start < 0:
        return ""
    rest = text[start + len(start_tag):]
    next_section = rest.find("\n[")
    return rest if next_section < 0 else rest[:next_section]

expected = None
if env_name.endswith("_doa"):
    expected = "doa"
elif env_name.endswith("_aac"):
    expected = "aac"

if expected is not None:
    section = _read_env_section_text(env_name)
    expected_define = f'-DDEVICE_PRODUCT=\\"{expected}\\"'
    has_expected_in_env_block = expected_define in section
    if not has_expected_in_env_block:
        print(
            f"[profile] ERROR: env '{env_name}' must declare {expected_define} "
            "inside its own [env:...] block in platformio.ini."
        )
        env.Exit(1)

if expected is not None and expected not in products:
    print(
        f"[profile] ERROR: env '{env_name}' expects DEVICE_PRODUCT='{expected}', "
        f"but got {products if products else ['aac(default)']}."
    )
    print("[profile] Fix build_flags/build_unflags in platformio.ini.")
    env.Exit(1)

print(
    f"[profile] env={env_name} device_product={effective_product} "
    f"(all={products if products else ['aac(default)']})"
)
