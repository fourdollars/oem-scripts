#!/usr/bin/python
#Rename the project
#Program goes over the files and renames them using bzr
#then it goes inside the file and cahnges all old names to new name
#
# Copyright (C) Canonical Inc.  <Alexander Wolfson> <alex.wolfson@canonical.com>
# This program is free software: you can redistribute it and/or modify it 
# under the terms of the GNU General Public License version 3, as published 
# by the Free Software Foundation.
# 
# This program is distributed in the hope that it will be useful, but 
# WITHOUT ANY WARRANTY; without even the implied warranties of 
# MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR 
# PURPOSE.  See the GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License along 
# with this program.  If not, see <http://www.gnu.org/licenses/>.
# TODO: now to use script you need to modify main/subst_list - add the ability to read configuration file
import os
import sys
import subprocess
import string
import traceback
class QuicklyRename(object):
    #A code to distiguish between text and binaries is taken from
    #http://code.activestate.com/recipes/173220-test-if-a-file-or-string-is-text-or-binary/
    #TODO:Unicode?
    cfgfile = 'quickly_project_rename.cfg'
    text_characters = "".join(map(chr, range(32, 127)) + list("\n\r\t\b"))
    _null_trans = string.maketrans("", "")

    def isTextfile(self, filename, blocksize = 512):
        print os.getcwd()
        return self.isText(open(filename).read(blocksize))

    def isText(self, s):
        if "\0" in s:
            return 0
        
        if not s:  # Empty files are considered text
            return 1

        # Get the non-text characters (maps a character to itself then
        # use the 'remove' option to get rid of the text characters.)
        t = s.translate(QuicklyRename._null_trans, QuicklyRename.text_characters)

        # If more than 30% non-text characters, then
        # this is considered a binary file
        if len(t)/len(s) > 0.30:
            return 0
        return 1

    def getNotInBzrFiles(self, path):
        #TODO: some more bzr API way?
        save_cwd = os.getcwd()
        os.chdir(path)
        try:
            return os.listdir('.')
            p1 = subprocess.Popen(["bzr", "ls", "--ignored", "--unknown"], stdout=subprocess.PIPE)
            #p2 = subprocess.Popen(["grep", "^?"], stdin=p1.stdout, stdout=subprocess.PIPE)
            output = p1.communicate()[0]
            return output.splitlines()
        finally:
            os.chdir(save_cwd)   
    def substAll(self, s, subst_list):
        for o,n in subst_list:
            s = s.replace(o, n)
        return s
    def processDir(self, path, subst_list):
        save_cwd = os.getcwd()
        os.chdir(path)
        print "=> Processing directory <%s>" % path 
        
        not_in_bzr = self.getNotInBzrFiles('.')
        print "not in bzr = ", not_in_bzr

        try:
            for fname in os.listdir('.'):
                if fname in (".bzr", QuicklyRename.cfgfile):
                    continue
                new_name = self.substAll(fname, subst_list)
                print "renaming and processing file <{0}> => <{1}>".format(fname, new_name) 
                if new_name != fname:
                    self.renameFile(fname, new_name, not_in_bzr)
                if os.path.isdir(new_name):
                    self.processDir(new_name, subst_list)
                    print "<= Back to directory", path 
                elif self.isTextfile(new_name):
                   self.renameInFile(new_name, subst_list)
        finally:
            os.chdir(save_cwd)   
    def renameFile(self, old_name, new_name, not_in_bzr):
        #Would me nice to use bzr API directly
        if old_name in not_in_bzr:
            os.rename(old_name, new_name)        
        else:
            subprocess.call(("bzr", "mv", old_name, new_name))
    def renameInFile(self, file_name, subst_list):
        ''' Rename all the instances of the old name to the new one according to the subst_list'''
        with open (file_name + "_new", "w") as fw:
            with open (file_name, "r") as fr:
                for line_r in fr:
                    line_w = self.substAll(line_r, subst_list)
                    fw.write (line_w)
        os.rename(file_name + "_new", file_name)
                               
def main():
    if len(sys.argv) != 2:
        usage='''
        USAGE: python quickly_project_rename PROJECT_DIRECTORY
        
        Put quickly_project_rename.cfg into PROJECT_DIRECTORY with lines:
        OLD_NAME=NEW_NAME
        
        like:
        
        old-name=new-name
        OldName=NewName
        Oldname=Newname
        old name=new name
        '''
        print usage
        exit (1)
    dir_to_process = sys.argv[1]
    subst_list=[]
    fname=dir_to_process + '/' + QuicklyRename.cfgfile
    try:
        with open(fname) as conf_file:
            for line in conf_file:
                line = line.strip()
                if line != "": #last line with \n only
                    subst_list.append(line.split('='))
    except IOError as (errno, strerror):
        print "open('{0}'), I/O error({1}): {2}".format(fname, errno, strerror)
        exit (1)
    #print subst_list
    #subst_list = (('apptime', 'apptimer'),('AppTime', 'AppTimer'), ('Apptime', 'Apptimer')) 

    print "\nreplacing:", subst_list, "in ", dir_to_process, "\nIf you don't like the result execute\n\nbzr revert\n\n", "Do you want to continue? (Yes/no)?>",
    answer = sys.stdin.readline().strip()
    if not (answer in ('Yes','yes')):
        print "exit"
        exit(1)
    qr = QuicklyRename()
    #print qr.not_in_bzr
    qr.processDir(dir_to_process, subst_list)    
if __name__ == "__main__":
    main()


