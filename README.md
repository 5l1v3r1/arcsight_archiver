Arcsight Archiver
==================
Backing up your ArcSight archive

Issue description
---------------------------------
Arcsight has an issue in archiving which is limit archiving space to 200GB even you have more space!.
The script will move taken archives to another place you specify.

* You can specify maximum number of source(arcsight default archiving path) and destination
* You can specify number of days to be kept (not to be moved to the destination)
* You can specify email for notifications


Requirements
------------
**From rubygems**

        gem install viewpoint parseconfig html-table

**Local gem installation**

        gem install parseconfig
        gem install html-table


**Requirements dependencies**

        viewpoint.gem
           |
           |--> nokogiri
           |      |-> mini_portile
           |--> mail
           |      |-> mime-types
           |      |-> treetop
           |      |-> polyglot
           |--> handsoap
           |--> rubyntlm
           |--> icalendar
           |--> httpclient
           |-->
           |




