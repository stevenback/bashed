# bashed
A version of the ed text editor written in pure bash.

This is a most definitely a nitch project.
The goal is to create a functional ed style line editor, but purely inside of bash and not rely on any external support programs like sed, awk or tr.
To make it clear, in no way is this meant to replace your normal day to day editor.
This is the editor of last resort when a system is so messed up, it can't run most applications and you were 'lucky' to get to a functional bash shell.
The inspiration for this editor is an old recovery mode that early versions of Solaris OS could get stuck in.
In that state, the only programs that could be run was a tiny handful of staticly linked utilities, which included the shell, some disk repair tools like fsck and a limited version of the mount command.  There wasn't even the most basic shell tools like, 'ls' or 'cat'.
Yes, a shell where even 'ls' didn't exist. To see what files where in a directory, you would use 'echo *' 
To replace the function of 'cat' you would write a quick 'while read line; do echo $line; done < file' 
You were most likely to end up in this mode if there was an error in the /etc/fstab file so you would end up using echo commands
to re-create that file, which could be tedious.

It's been years since I've been stuck in that mode, but memories of working in it, inspired this minimal ed editor.
