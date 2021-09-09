__version__ = "1.13"

ALLOWED_KERNEL_META_LIST = (
    "linux-oem-20.04d",
    "linux-oem-20.04c",
    "linux-oem-20.04b",
    "linux-oem-20.04",
    "linux-generic-hwe-20.04",
)

SUBSCRIBER_LIST = ("oem-solutions-engineers", "ubuntu-sponsors", "ubuntu-desktop")

TAG_LIST = ["oem-meta-packages", "oem-priority", f"oem-scripts-{__version__}"]


# Python 3.9 supports this.
def remove_prefix(s, prefix):
    return s[len(prefix) :] if s.startswith(prefix) else s


def yes_or_ask(yes: bool, message: str) -> bool:
    if yes:
        print(f"> \033[1;34m{message}\033[1;0m (y/n) y")
        return True
    while True:
        res = input(f"> \033[1;34m{message}\033[1;0m (y/n) ").lower()
        if res not in {"y", "n"}:
            continue
        if res == "y":
            return True
        else:
            return False
