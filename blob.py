import subprocess
import sys

sys.stderr.write("* Executing %s\n" % sys.argv[1:])
sys.stderr.flush()
d = subprocess.Popen(
    [
        "cmd.exe", "/C", "start", "/MIN", "/NORMAL",
        "perl", "../blob.pl",
     ] + sys.argv[1:],
    close_fds=True,
    stdin=None,stdout=None,stderr=None,
    creationflags=subprocess.CREATE_NEW_CONSOLE,
    env=None,
    )
d.wait()
sys.stderr.write("* Done\n")
sys.stderr.flush()
