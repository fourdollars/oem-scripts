#!/usr/bin/python
import sys
from launchpadlib.launchpad import Launchpad
launchpad = Launchpad.login_with('test', "production")


def getValueWithDefault(prompt, default):
    "Prompt user for value, with default"
    result = raw_input("%s [%s]> " % (prompt, default))
    return result and result or default


from_pocket = getValueWithDefault("From Pocket (Proposed|Updates|Release...)?",
                                  "Proposed")

team = None
while not team:
    team_name = getValueWithDefault("PPA owning team?", "oem-archive")
    try:
        team = launchpad.people[team_name]
    except e:
        print("Invalid team")

ppa = None
while not ppa:
    PPA_name = getValueWithDefault("PPA name?", "sutton")
    try:
        ppa = team.getPPAByName(name=PPA_name)
    except e:
        print("Invalid ppa name")

to_pocket = getValueWithDefault("To Pocket (Proposed|Updates|Release...)?",
                                "Release")
to_series = getValueWithDefault("To Series?", "precise")

# Get link to ubuntu archive
ubuntu = launchpad.distributions["Ubuntu"]
archive = ubuntu.archives[0]  # archives[0] is 'primary' (vs. partner)

while True:
    package_name = getValueWithDefault("Package Name?", "linux")

    # View packages in ubuntu archive
    pkgs = archive.getPublishedSources(
        source_name=package_name, pocket=from_pocket, status="Published")

    while True:
        print("\n----")
        names = [p.display_name for p in pkgs]
        for i, name in enumerate(names):
            print " %d: %s" % (i, name)
        print("----\n")
        i = raw_input("Enter pkg to transfer (0..%d/[Q]uit/[a]nother)> "
                      % (len(names) - 1))
        try:
            pkg = pkgs[int(i)]

            print("Ready to copy package %s" % pkg.display_name)
            if raw_input("Confirm: [Y/n]").lower()[:1] != 'n':
                pass
                ppa.syncSource(from_archive=archive,
                               include_binaries=True,
                               source_name=pkg.display_name.split()[0],
                               to_pocket=to_pocket,
                               to_series=to_series,
                               version=pkg.source_package_version)

        except (ValueError, IndexError):
            if i.lower()[:1] == 'q':
                print("Quitting")
                sys.exit(0)
            if i.lower()[:1] == 'a':
                break
            print("invalid input\n")
