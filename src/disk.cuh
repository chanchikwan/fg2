/* Copyright (C) 2012 Chi-kwan Chan
   Copyright (C) 2012 NORDITA

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

#define PARA_R0 K(3.0)

struct state {
  R lnd;           // ln(density)
  R v_r, v_t, Omg; // radial, altitude, and angular velocity
  R lne;           // ln(specific_thermal_energy)
};

#ifdef KICK_CU ///////////////////////////////////////////////////////////////

__device__ __constant__ R para_M     = 1.0;       // mass of central black hole
__device__ __constant__ R para_rS    = 2.0;       // Schwarzschild radius
__device__ __constant__ R para_gamma = 5.0 / 3.0; // ratio of specific heats

__device__ __constant__ R para_dd    = 0.0;       // simple density diffusion
__device__ __constant__ R para_ad    = 0.0;       // simple viscosity
__device__ __constant__ R para_vd    = 0.0;       // simple viscosity
__device__ __constant__ R para_ld    = 0.0;       // simple viscosity
__device__ __constant__ R para_ed    = 0.0;       // simple conductivity

static __device__ S eqns(const S *u, const Z i, const Z j, const Z s)
{
  S dt = {0.0, 0.0, 0.0, 0.0};

  const S d1 = {D1(lnd), D1(v_r), D1(v_t), D1(Omg), D1(lne)}; // 45 FLOP
  const S d2 = {D2(lnd), D2(v_r), D2(v_t), D2(Omg), D2(lne)}; // 45 FLOP

  const R r = PARA_R0 * exp((i + K(0.5)) * Delta1); // 4 FLOP
  const R t =               (j + K(0.5)) * Delta2 ; // 2 FLOP
  R div_v;

  // Advection and pseudo force: 52 FLOP
  {
    const R v_r = u->v_r;
    const R v_t = u->v_t;

    dt.lnd -= (v_r * d1.lnd + v_t * d2.lnd) / r;
    dt.v_r -= (v_r * d1.v_r + v_t * d2.v_r) / r;
    dt.v_t -= (v_r * d1.v_t + v_t * d2.v_t) / r;
    dt.Omg -= (v_r * d1.Omg + v_t * d2.Omg) / r;
    dt.lne -= (v_r * d1.lne + v_t * d2.lne) / r;

    const R Omg   = u->Omg;
    const R up2   = r * r * Omg * Omg;
    const R cot_t = cos(t) / sin(t);

    dt.v_r +=       (   v_t * v_t + up2        ) / r;
    dt.v_t -=       (   v_r * v_t - up2 * cot_t) / r;
    dt.Omg -= Omg * (K(2.0) * v_r + v_t * cot_t) / r;

    div_v = (d1.v_r + d2.v_t + K(2.0) * v_r + cot_t * v_t) / r;
  }

  // Compressible/pressure effects: 14 FLOP
  {
    const R gamma_1 = para_gamma - K(1.0);
    const R temp    = gamma_1 * exp(u->lne);

    dt.lnd -= div_v;
    dt.v_r -= temp * (d1.lnd + d1.lne) / r;
    dt.v_t -= temp * (d2.lnd + d2.lne) / r;
    dt.lne -= div_v * gamma_1;
  }

  // External force (gravity): 4 FLOP
  {
    const R tmp = r - para_rS;

    dt.v_r -= para_M / (tmp * tmp);
  }

  // Simple diffusion --- take care ln() but no geometric factors: 130 FLOP
  {
    dt.lnd += para_dd * (D11(lnd) + D22(lnd) + d1.lnd*d1.lnd + d2.lnd*d2.lnd);
    dt.v_r += para_ad * (D11(v_r) + D22(v_r));
    dt.v_t += para_vd * (D11(v_t) + D22(v_t));
    dt.Omg += para_ld * (D11(Omg) + D22(Omg));
    dt.lne += para_ed * (D11(lne) + D22(lne) + d1.lne*d1.lne + d2.lne*d2.lne);
  }

  return dt;
}

#elif defined(MAIN_CPP) //////////////////////////////////////////////////////

static void config(void)
{
  using namespace global;

  // Simulate the full pi wedge; make grid cells more-or-less square
  l2 = M_PI;
  const R hd2 = 0.5 * l2 / n2;
  const R hd1 = log(hd2 + sqrt(hd2 * hd2 + 1.0));
  l1 = 2.0 * hd1 * n1;

  // Neumann and reflective boundary conditions
  p1 = 0;
  p2 = 0;

  // Compute floating point operation and bandwidth per step
  const Z m1 = n1 + ORDER;
  const Z m2 = n2 + ORDER;
  flops = 3 * ((n1 * n2) * (296 + NVAR * 2.0)); // assume FMA
  bps   = 3 * ((m1 * m2) * 1.0 +
               (n1 * n2) * 5.0 +
               (m1 + m2) * 2.0 * ORDER) * NVAR * sizeof(R) * 8;

  // Set device constant for kernels
  const R Delta[] = {l1 / n1, l2 / n2};
  cudaMemcpyToSymbol("Delta1", Delta+0, sizeof(R));
  cudaMemcpyToSymbol("Delta2", Delta+1, sizeof(R));
}

#elif defined(INIT_CPP) //////////////////////////////////////////////////////

static R M;
static R rS;
static R Gamma;

static S ad_hoc(R lnr, R theta)
{
  const R r   = PARA_R0 * exp(lnr);
  const R Omg = sin(theta) * sqrt(M / r) / r;

  return (S){0.0, 0.0, 0.0, Omg, 0.0};
}

static S Hawley(R lnr, R theta)
{
  const R r     = PARA_R0 * exp(lnr);
  const R cyl_r = r * sin(theta);

  // We use something very similar to the steady state torus solution
  // given by Hawley (2000) as our initial condition.  The density is
  // given implicitly by equation (7) in the paper:
  //
  //   Gamma K P / (Gamma - 1) rho = C - Psi - lK^2 / (2q - 2) R^(2q - 2)
  //
  // By comparing the dimensions of different terms on the right hand
  // side, it is clear that R must be dimensionless.  Indeed, Hawley
  // choice the Schwarzschild radius rS = 1.  This automatically gives
  // Psi ~ c^2.
  //
  // Using P = K rho^Gamma, the "pressure acceleration" from the left
  // hand side is
  //
  //   grad(LHS) / rho = Gamma K^2 rho^(Gamma - 2) grad(rho)
  //
  // Comparing this term with grad(P) / rho, it seems the extra
  // polytropic constant "K" is a typo.  We will drop it when we
  // construct our initial condition.
  //
  // The integration constant C controls the size of the torus.  In
  // the Hawley (2000) paper, it is solved by fixing the inner edge of
  // the torus.  Nevertheless, this constant physically controls the
  // temperature, which gives raise to the scale height etc.  To see
  // this, the centrifugal support *almost* cancels gravity at the
  // pressure maximum so we left with
  //
  //   Gamma P / (Gamma - 1) rho = Gamma kB T / (Gamma - 1) mu mH ~ C
  //
  // The contant C determines the temperature at the pressure maximum,
  // and vice versa.  In this file, we will use the temperature, or
  // specific thermal energy, at the pressure maximum, tmp0, (and
  // other parameters) to choose C.

  // Setup parameters
  const R q0 =  2.0;
  const R r0 = 16.0;
  const R d0 =  1.0;
  const R e0 =  0.01;
  const R d1 =  0.01;
  const R e1 =  0.01;

  // Shorthands
  const R g1 = Gamma - 1.0;
  const R q1 = 2.0 * q0 - 2.0;

  // "Specific angular momentum" at pressure maximum: taking the
  // derivative of the right hand side of equation (7) in Hawley
  // (2000), we know the following holds at the pressure maximum
  //
  //   G M / (r - rS)^2 = lK^2 / r^(2 q - 1)
  //
  // Therefore, the following formula is exact and it fixes the unit
  // problem

  const R lK = sqrt(M * pow(r0, q1) * r0) / r0;

  // We drop the extra polytropic constant in the left hand side.  We
  // also use specific thermal energy to specify the polytropic and
  // integration constant

  const R K    = (g1 * e0) / pow(d0, g1);
  const R c0   = Gamma * e0 - M / r0 + lK * lK / (pow(r0,    q1) * q1);
        R prof =         c0 + M / r  - lK * lK / (pow(cyl_r, q1) * q1);

  if(prof > 0.0) prof =  pow( prof * g1 / (Gamma * K), 1.0 / g1);
  else           prof = -pow(-prof * g1 / (Gamma * K), 1.0 / g1);

  R den, Omg, eng;
  if(prof > d0 * d1) {
    den = prof;
    Omg = lK * pow(cyl_r, -q0);
    eng =  K * pow(den, g1) / g1;
  } else {
    den = d0 * d1;
    Omg = 0.0;
    eng = K * pow(den, g1) / g1 * e1;
  }

  return (S){log(den), 0.0, 0.0, Omg, log(eng)};
}

static S (*pick(const char *name))(R, R)
{
  cudaMemcpyFromSymbol(&M,     "para_M",     sizeof(R));
  cudaMemcpyFromSymbol(&rS,    "para_rS",    sizeof(R));
  cudaMemcpyFromSymbol(&Gamma, "para_gamma", sizeof(R));

  if(!strcmp(name, "Hawley")) return Hawley; // hydrostatic Hawley (2000) torus

  return ad_hoc; // default
}

#endif ///////////////////////////////////////////////////////////////////////
