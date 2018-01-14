#include <sys/personality.h>
#include <stdarg.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdio.h>

/* Disable address randomization in the current process.  Return true
   if addresses were randomized but this has been disabled, false
   otherwise. */
bool
disable_address_randomization (void)
{
  int pers = personality (0xffffffff);
  if (pers < 0)
    return false;
  int desired_pers = pers | ADDR_NO_RANDOMIZE;

  /* Call 'personality' twice, to detect buggy platforms like WSL
     where 'personality' always returns 0.  */
  return (pers != desired_pers
	  && personality (desired_pers) == pers
	  && personality (0xffffffff) == desired_pers);
}

void die (const char *format, ...)
{
  va_list ap;
  int length;

  va_start (ap, format);
  length = vfprintf (stderr, format, ap);
  va_end (ap);

  exit (1);
}

int main()
{
    int pers = personality (0xffffffff);
    if (pers < 0)
        die ("personality(FFF): %d\n", pers);
    int desired_pers = pers | ADDR_NO_RANDOMIZE;
    if (desired_pers == pers)
        die ("personality already includes ADDR_NO_RANDOMIZE\n");

    if (desired_pers != (pers = personality (desired_pers))) {
        if (pers == -1)
            perror ("personality");
        die ("failed to enable ADDR_NO_RANDOMIZE (%X)\n", pers);
    }

    printf("Got ADDR_NO_RANDOMIZE successfully\n");
    return 0;
}
