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

#include <cstdlib>
#include <limits>
#include <cuda_runtime.h>
#include "fg2.h"

static void done(void)
{
  if(global::host)
   free(global::host - HALF * (global::s + NVAR));
  cudaFree(global::v - HALF * (global::s + NVAR));
  cudaFree(global::u - HALF * (global::s + NVAR));
}

size_t setup(const Z n1, const Z n2)
{
  if(atexit(done)) abort();

  const Z m1 = (global::n1 = n1) + ORDER;
  const Z m2 = (global::n2 = n2) + ORDER;

  // Grid and block sizes for rolling cache kernel
  Z d; cudaGetDevice(&d);
  cudaDeviceProp dev; cudaGetDeviceProperties(&dev, d);
  Z w = dev.multiProcessorCount;
  for(Z i = 2; dev.multiProcessorCount % i == 0; i *= 2) w /= 2;
  for(Z h = 0, i = 1; ; ++i) {
    Z g = NVAR * sizeof(R) * (ORDER + i);
    Z j = (dev.sharedMemPerBlock - SYS) / g - ORDER; if(j > 512) j = 512;
    if(i * j > dev.regsPerBlock / REG) j = dev.regsPerBlock / (REG * i);
    if(i * j > dev.maxThreadsPerBlock) j = dev.maxThreadsPerBlock / i;
    j = (j / dev.warpSize) * dev.warpSize; // multiple of warp size
    while(j && (n2 - 1) / j + 1 < w) j = (j / dev.warpSize - 1) * dev.warpSize;
    if(i * j <= h) break; // if new block size use less threads, break
    h = i * j;
    global::b1 = i;
    global::b2 = j;
    global::sz = g * (ORDER + j);
  }
  global::g2 = (n2 - 1) / global::b2 + 1;
  global::g1 = (dev.multiProcessorCount - 1) / global::g2 + 1;

  // State variable
  void *u; size_t upitch;
  if(cudaSuccess != cudaMallocPitch(&u, &upitch, NVAR * sizeof(R) * m2, m1) ||
     upitch % sizeof(R)) return 0;
  global::s = upitch / sizeof(R);
  global::u = (R *)u + HALF * (global::s + NVAR);

  // Storage for finite difference or swap space for finite volume
  void *v; size_t vpitch;
  if(cudaSuccess != cudaMallocPitch(&v, &vpitch, NVAR * sizeof(R) * m2, m1) ||
     vpitch % sizeof(R)) return 0;
  if(vpitch != upitch) return 0;
  global::v = (R *)v + HALF * (global::s + NVAR);

  // Allocate host memory
  const size_t n = global::s * m1;
  R *h = (R *)malloc(sizeof(R) * n);
  if(NULL == h) return 0;
  global::host = h + HALF * (global::s + NVAR);

  // Initialize all arrays to -FLT_MAX or -DBL_MAX
  for(size_t i = 0; i < n; ++i) h[i] = -std::numeric_limits<R>::max();
  cudaMemcpy(u, h, sizeof(R) * n, cudaMemcpyHostToDevice);
  cudaMemcpy(v, h, sizeof(R) * n, cudaMemcpyHostToDevice);

  // Return size of device memory
  return 2 * sizeof(R) * n;
}
