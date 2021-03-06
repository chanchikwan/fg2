/* Copyright (C) 2011,2012 Chi-kwan Chan
   Copyright (C) 2011,2012 NORDITA

   This file is part of fg2.

   Fg2 is free software: you can redistribute it and/or modify it
   under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   Fg2 is distributed in the hope that it will be useful, but WITHOUT
   ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
   or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
   License for more details.

   You should have received a copy of the GNU General Public License
   along with fg2.  If not, see <http://www.gnu.org/licenses/>. */

#ifndef FG2_H
#define FG2_H

#define REG  60 // number of regsiter by used by the kick kernel
#define SYS  16 // size of system shared memory used by the kick kernel
#define BSZ 256 // default block size used by the drift kernel

#ifndef ORDER
#define ORDER 6
#endif

#if (ORDER) < 0 || (ORDER) % 2
#error !!! ORDER must be positive and even !!!
#else
#define HALF ((ORDER) / 2)
#endif

typedef int Z;
#if defined(DOUBLE) || defined(OUBLE) // so -DOUBLE works
typedef double      R;
typedef long double E;
#define K(x) (x)
#else
typedef float  R;
typedef double E;
#define K(x) (x##f)
#endif

typedef struct state S;
#define NVAR (sizeof(S) / sizeof(R))

namespace global {
  extern Z n1, n2, s;          // resolution, stride in R
  extern Z g1, g2, b1, b2, sz; // grid and block dim, shared memory in byte
  extern R *u, *v, *host;      // state, swap, and host array

  extern R l1, l2, c;          // box size, Courant number
  extern int p1, p2;           // periodic boundary conditions
  extern double flops, bps;    // float operation and bit per *step*
}

void print(const char *, ...);
void error(const char *, ...);
void usage(const char *);

int  atop  (const char *); // argument to periodic boundary condition
void banner(const char *, char, char);
int  exist (const char *);
Z    frame (const char *);
const char *name(Z);

void init(const char *);
E    load(const char *);
void dump(const char *, E);

const char *para(const char *);
size_t setup(Z, Z);
void config(void);
int  solve (E, E, Z, Z);
E    getdt (void);
int  step  (E, E);

void Euler(R *, R);
void bcond(R *, int, int);
void kick (R *, const R *, R, R);
void drift(R *, const R *, R);

#include <state.h>

#endif // FG2_H
