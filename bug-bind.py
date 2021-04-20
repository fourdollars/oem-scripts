#!/usr/bin/python3
# Copyright 2018-2020 Canonical
# Helper script to `bind' private to public bug.

import argparse
import logging
import re

import lazr.restfulclient.resource
from oem_scripts.LaunchpadLogin import LaunchpadLogin

HWE_PUBLIC_PROJECT = 'hwe-next'
OEM_PUBLIC_PROJECT = 'oem-priority'

lp = None
log = logging.getLogger('bug-bind-logger')
log.setLevel(logging.DEBUG)
logging.basicConfig(format='%(levelname)s %(asctime)s - %(message)s',
                    datefmt='%m/%d/%Y %I:%M:%S %p')


def link_bugs(public_bugnum, privates, ihv):
    assert(public_bugnum.isdigit())
    login = LaunchpadLogin()
    lp = login.lp
    pub_bug = lp.bugs[public_bugnum]

    tag = "X-HWE-Bug: Bug #" + public_bugnum

    # Add X-HWE-Bug: tag to description.
    for priv in privates:
        assert(priv.isdigit())
        bug = lp.bugs[priv]

        if re.search(tag, bug.description) is None:
            # Add the referenced public bug to the private bug, if it's not in already.
            bug.description += "\n\n{}\n".format(tag)
            bug.lp_save()
        else:
            log.warning("Bug already linked to public bug " + tag)

        if ihv == "hwe":
            hwe_next = lp.projects[HWE_PUBLIC_PROJECT]
            sub_url = "%s~%s" % (lp._root_uri, 'canonical-hwe-team')
            pub_bug.subscribe(person=sub_url)
            remote_bug_tag(pub_bug, 'hwe-needs-public-bug')
        elif ihv == "swe":
            hwe_next = lp.projects[OEM_PUBLIC_PROJECT]
            sub_url = "%s~%s" % (lp._root_uri, 'oem-solutions-engineers')
            pub_bug.subscribe(person=sub_url)
            remote_bug_tag(pub_bug, 'swe-needs-public-bug')
        else:
            if lp.projects[ihv]:
                hwe_next = lp.projects[ihv]
                remote_bug_tag(pub_bug, 'hwe-needs-public-bug')
            else:
                log.error('Project ' + ihv + ' not defined')

        add_bug_tags(pub_bug, ['originate-from-' + str(bug.id),
                               bug.bug_tasks_collection[0].bug_target_name,  # OEM codename
                               'oem-priority'])

    add_bug_task(pub_bug, hwe_next)


def link_priv_bugs(main_bugnum, privates, ihv):
    assert(main_bugnum.isdigit())
    login = LaunchpadLogin()
    lp = login.lp
    main_bug = lp.bugs[main_bugnum]

    tag = "X-SWE-Bug: Bug #" + main_bugnum

    # Add X-HWE-Bug: tag to description.
    for priv in privates:
        assert(priv.isdigit())
        bug = lp.bugs[priv]

        if re.search(tag, bug.description) is None:
            # Add the referenced main bug to the private bug, if it's not in already.
            bug.description += "\n\n{}\n".format(tag)
            bug.lp_save()
        else:
            log.warning("Bug already linked to main bug " + tag)

        add_bug_tags(main_bug, ['originate-from-' + str(bug.id)])


def add_bug_task(bug, bug_task):
    assert(type(bug_task) == lazr.restfulclient.resource.Entry)

    # Check if already have the requested
    for i in bug.bug_tasks:
        if bug_task.name == i.bug_target_name:
            log.warning('Also-affects on {} already complete.'.format(bug_task))
            return
    bug.addTask(target=bug_task)
    bug.lp_save()
    log.info('Also-affects on {} successful.'.format(bug_task))


def remote_bug_tag(bug, tag):
    """ remove tag from the bug """
    if tag in bug.tags:
        tags = bug.tags
        tags.remove(tag)
        bug.tags = tags
        bug.lp_save()


def add_bug_tags(bug, tags):
    """ add tags to the bug. """
    log.info('Add tags {} to bug {}'.format(tags, bug.web_link))
    new_tags = []
    for tag_to_add in tags:
        if tag_to_add not in bug.tags:
            new_tags.append(tag_to_add)
    bug.tags = bug.tags + new_tags
    bug.lp_save()


if __name__ == '__main__':
    description = """bind private bugs with pubilc bug
bud-bind -p bugnumber private_bugnumber1 private_bugnumber2"""
    help = """The expected live cycle of an oem-priority bug is:
    1. SWE/HWE manually tag hwe-need-public/swe-need-public on the existed private bug,
    2. SWE/HWE manually create a public bug.
    3. Use bug-bind to bind public and private bug."""

    parser = argparse.ArgumentParser(description=description, epilog=help, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('-m', '--main', help='main bug for private bugs')
    parser.add_argument('-p', '--public', help='The public bug number')
    parser.add_argument('-i', '--ihv', help='Launchpad project name for IHV\nExpecting "swe", "hwe", "intel", "amd", "nvidia", "lsi", "emulex"', default='swe')
    parser.add_argument('-v', '--vebose', help='shows debug messages', action='store_true', default=False)
    # TODO
    # parser.add_argument('-c', '--clean', help='unlnk the bug between public and private', action='store_true', default=False)

    args, private_bugs = parser.parse_known_args()
    if args.vebose:
        log.setLevel(logging.DEBUG)
    if args.ihv not in ["swe", "hwe", "intel", "amd", "nvidia", "lsi", "emulex"]:
        raise Exception('Expecting "swe", "hwe", "intel", "amd", "nvidia", "lsi", "emulex" for ihv')
    if len(private_bugs) == 0:
        parser.error("must provide private bug numbers.")
    if args.main:
        link_priv_bugs(args.main, private_bugs, args.ihv)
    else:
        link_bugs(args.public, private_bugs, args.ihv)
