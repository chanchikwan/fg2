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

__device__ __constant__ R para_M     = 1.0;       // mass of central black hole
__device__ __constant__ R para_rS    = 2.0;       // Schwarzschild radius
__device__ __constant__ R para_rin   = 3.0;       // location of inner boundary

__device__ __constant__ R para_gamma = 5.0 / 3.0; // ratio of specific heats
__device__ __constant__ R para_nus   = 0.0;       // shear  viscosity
__device__ __constant__ R para_nub   = 0.0;       // bulk   viscosity
__device__ __constant__ R para_kappa = 0.0;       // thermal conductivity
__device__ __constant__ R para_alpha = 0.01;      // Shakura-Sunyaev alpha

__device__ __constant__ R para_ar    = 1.0e+8;    // radiation density constant
__device__ __constant__ R para_icool = 1.0;       // inverse cooling timescale

__device__ __constant__ R para_dd    = 1.0e-4;    // simple density diffusion
__device__ __constant__ R para_nu    = 2.0e-4;    // simple viscosity
__device__ __constant__ R para_ed    = 5.0e-4;    // simple energy diffusion
__device__ __constant__ R para_rd    = 5.0e-4;    // simple radiation diffusion

static __device__ S eqns(const S *u, const Z i, const Z j, const Z s)
{
  S dr, dz, dt = {0.0, 0.0, 0.0, 0.0, 0.0};
  R sint, cost, r, nuSS;

  const R sphr = para_rin * exp((i + K(0.5)) * Delta1); // 4 FLOP

  // Derivatives: 161 FLOP
  {
    const S d1 = {D1(lnd), D1(ur), D1(uz), D1(Omg), D1(lne), D1(lner)};
    const S d2 = {D2(lnd), D2(ur), D2(uz), D2(Omg), D2(lne), D2(lner)};

    const R theta = (j + K(0.5)) * Delta2 ;
    sincos(theta, &sint, &cost);
    r = sphr * sint;

    dr.lnd  = (sint * d1.lnd  + cost * d2.lnd ) / sphr;
    dr.ur   = (sint * d1.ur   + cost * d2.ur  ) / sphr;
    dr.uz   = (sint * d1.uz   + cost * d2.uz  ) / sphr;
    dr.Omg  = (sint * d1.Omg  + cost * d2.Omg ) / sphr;
    dr.lne  = (sint * d1.lne  + cost * d2.lne ) / sphr;
    dr.lner = (sint * d1.lner + cost * d2.lner) / sphr;

    dz.lnd  = (cost * d1.lnd  - sint * d2.lnd ) / sphr;
    dz.ur   = (cost * d1.ur   - sint * d2.ur  ) / sphr;
    dz.uz   = (cost * d1.uz   - sint * d2.uz  ) / sphr;
    dz.Omg  = (cost * d1.Omg  - sint * d2.Omg ) / sphr;
    dz.lne  = (cost * d1.lne  - sint * d2.lne ) / sphr;
    dz.lner = (cost * d1.lner - sint * d2.lner) / sphr;
  }

  // Advection and pseudo-force: 27 FLOP
  {
    const R ur  = u->ur ;
    const R uz  = u->uz ;
    const R Omg = u->Omg;

    dt.lnd -= ur * dr.lnd + uz * dz.lnd;
    dt.ur  -= ur * dr.ur  + uz * dz.ur - Omg * Omg * r;
    dt.uz  -= ur * dr.uz  + uz * dz.uz;
    dt.Omg -= ur * dr.Omg + uz * dz.Omg + K(2.0) * ur * Omg / r;
    dt.lne -= ur * dr.lne + uz * dz.lne;
  }

  // Compressible/pressure effects: 16 FLOP
  {
    const R gamma1 = para_gamma - K(1.0);
    const R temp   = gamma1 * exp(u->lne);
    const R ur_r   = u->ur / r;
    const R div_u  = dr.ur + dz.uz + ur_r;

    dt.lnd -= div_u;
    dt.ur  -= temp * (dr.lnd + dr.lne);
    dt.uz  -= temp * (dz.lnd + dz.lne);
    dt.lne -= div_u * gamma1;


  // Total shear viscosity = molecular + Shakura-Sunyaev: 6 FLOP
    nuSS = para_alpha * para_gamma * temp * r * sqrt(r / para_M);


  // Non-ideal effects (depend on density and temperature): 48 FLOP

    const R Srr =  dr.ur - div_u  / K(3.0);
    const R Szz =  dz.uz - div_u  / K(3.0);
    const R Spp =  ur_r  - div_u  / K(3.0);
    const R Srz = (dz.ur + dr.uz) / K(2.0);
    const R szp =  dz.Omg         / K(2.0); // == Szp / r
    const R spr =  dr.Omg         / K(2.0); // == Spr / r
    const R two_nus = K(2.0) * (para_nus + nuSS);

    dt.ur  += two_nus * (Srr * dr.lnd + Srz * dz.lnd);
    dt.uz  += two_nus * (Srz * dr.lnd + Szz * dz.lnd);
    dt.Omg += two_nus * (spr * dr.lnd + szp * dz.lnd);
    dt.lne += (gamma1 / temp) *
      (two_nus * (Srr * Srr + Szz * Szz + Spp * Spp +
        K(2.0) * (Srz * Srz +(szp * szp + spr * spr)* r * r)) +
       para_nub * div_u * div_u);
  }

  // Non-ideal effects (only depend on velocity): 157 FLOP
  {
    const R d11_ur = D11(ur), d11_uz = D11(uz);
    const R d12_ur = D12(ur), d12_uz = D12(uz);
    const R d22_ur = D22(ur), d22_uz = D22(uz);

    const R tmp1 = (para_nus + nuSS) / (sphr * sphr) + para_nu;
    const R tmp2 = (para_nus + nuSS) / r;

    dt.ur  += tmp1 * (d11_ur   + d22_ur  ) + tmp2 * (dr.ur - u->ur / r);
    dt.uz  += tmp1 * (d11_uz   + d22_uz  ) + tmp2 * (dr.uz            );
    dt.Omg += tmp1 * (D11(Omg) + D22(Omg)) + tmp2 * (dr.Omg * K(3.0)  );

    const R cr = cost / sphr, sr = sint / sphr;
    const R cc = cr * cr, cs = cr * sr, ss = sr * sr;
    const R c2 = cc - ss, s2 = K(2.0) * cs;

    const R drr_ur = ss*d11_ur + cc*d22_ur + s2*d12_ur + cr*dz.ur - sr*dr.ur;
    const R drz_ur = cs*(d11_ur - d22_ur)  + c2*d12_ur - cr*dr.ur - sr*dz.ur;
    const R drz_uz = cs*(d11_uz - d22_uz)  + c2*d12_uz - cr*dr.uz - sr*dz.uz;
    const R dzz_uz = cc*d11_uz + ss*d22_uz - s2*d12_uz - cr*dz.uz + sr*dr.uz;
    const R mixed  = (para_nus + nuSS) / K(3.0) + para_nub;

    dt.ur += mixed * (drr_ur + drz_uz + (dr.ur - u->ur / r) / r);
    dt.uz += mixed * (drz_ur + dzz_uz +  dz.ur              / r);
  }

  // Density diffusion and thermal conductivity: 103 FLOP
  {
    const R sphr_2   = sphr * sphr;
    const R d_lnd_2  = dr.lnd  * dr.lnd  + dz.lnd  * dz.lnd;
    const R d_lne_2  = dr.lne  * dr.lne  + dz.lne  * dz.lne;
    const R d_lner_2 = dr.lner * dr.lner + dz.lner * dz.lner;
    const R ed       = para_ed +
      (para_kappa * (para_gamma - K(1.0)) + para_gamma * nuSS) / sphr_2;

    dt.lnd  += para_dd * (D11(lnd ) + D22(lnd ) + d_lnd_2  * sphr_2);
    dt.lne  +=      ed * (D11(lne ) + D22(lne ) + d_lne_2  * sphr_2);
    dt.lner += para_rd * (D11(lner) + D22(lner) + d_lner_2 * sphr_2);
  }

  // Radiation force and heating or cooling: (23 FLOP)
  {
    const R den     = exp(u->lnd );
    const R eng     = exp(u->lne );
    const R rad     = exp(u->lner);

    const R lambda  = K(1.0) / K(3.0); // flux limiter in diffusion regime

    const R temp    = (para_gamma - K(1.0)) * eng;
    const R temp2   = temp * temp;
    const R heating = para_icool * (rad - para_ar * temp2 * temp2 / den);

    dt.ur   -= lambda * rad * (dr.lnd + dr.lne);
    dt.uz   -= lambda * rad * (dz.lnd + dz.lne);
    dt.lne  += heating / eng;
    dt.lner -= heating / rad;
  }

  // External force: 7 FLOP
  {
    const R tmp = sphr - para_rS;
    const R gr  = para_M / (tmp * tmp);

    dt.ur -= sint * gr;
    dt.uz -= cost * gr;
  }

  return dt;
}
