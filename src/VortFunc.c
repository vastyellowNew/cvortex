#include "libcvtx.h"
/*============================================================================
VortFunc.c

Common functions used to regularise vortex particles.

If we have a vorticity field omega(x) comprised of particles with vorticity
alpha_i, regularisation zeta(rho), where rho is the distance between x_i
and measurement point x divided by regularisation distance sigma then
omega(x) = sum( zeta(rho_i) * alpha_i )

These regularisation function are given by zeta, but exclude the 4*pi
part - that constant is in the evaluation bits.

The velocity includes a function g(rho) defined by
zeta(rho) = 1/rho^2 * dg/drho
again excluding the 4 pi bit.

For the particle strenght exchange schmeme another funcion eta(rho) is
required.
eta(rho) = -1/rho * (dzeta/drho)

Copyright(c) 2018-2020 HJA Bird

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files(the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions :

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
============================================================================*/

#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#define SQRTF_2_OVER_PI 0.7978845608028654f
#define RECIP_SQRTF_2 0.7071067811865475f

static float warn_bad_eta_fn(float rho) {
	static int warned = 0;
	assert(0 && "Vortex regularisation function had no viscous method!");
	if (warned == 0) {
		fprintf(stderr, "Tried to calculated perform viscous calculations "
			"with inapproriate vortex regularisation function!\n"
			"Modelling as invicid.\n\n");
		warned = 1;
	}
	return 0.f;
}

static float g_singular_3D(float rho) {
	return 1.f;
}

static float zeta_singular_3D(float rho) {
	return 0.f;
}

static void combined_singular_3D(float rho, float* g, float* zeta) {
	*g = 1.f;
	*zeta = 0.f;
	return;
}

static float g_singular_2D(float rho) {
	return 1.f;
}

static float g_winckel_3D(float rho) {
	float a, b, c, d;
	assert(rho >= 0 && "Rho should not be -ve");
	a = (rho * rho) + 2.5f;
	b = a * rho * (rho * rho);
	c = (rho * rho) + 1.f;
	d = b * powf(c, -2.5f);
	return d;
}

static float zeta_winckel_3D(float rho) {
	float a, b, c;
	assert(rho >= 0 && "Rho should not be -ve");
	a = rho * rho + 1.f;
	b = powf(a, -3.5f);
	c = 7.5f * b;
	return c;
}

static float eta_winckel_3D(float rho) {
	float a, b, c;
	assert(rho >= 0 && "Rho should not be -ve");
	a = 52.5f;
	b = rho * rho + 1.f;
	c = powf(b, -4.5f);
	return a * c;
}

static void combined_winckel_3D(float rho, float* g, float* zeta) {
	assert(rho >= 0 && "Rho should not be -ve");
	*g = g_winckel_3D(rho);
	*zeta = zeta_winckel_3D(rho);
	return;
}

static float g_winckel_2D(float rho) {
	float num, denom;
	num = (rho * rho) * (rho * rho) + (rho * rho) * 2.f;
	denom = (rho * rho) * (rho * rho) + 2.f * (rho * rho) + 1.f;
	return num / denom;
}

static float eta_winckel_2D(float rho) {
	assert(rho >= 0 && "Rho should not be -ve");
	float a, a2, b, c;
	a = rho * rho + 1.f;
	a2 = 1.f / (a * a);
	c = 24.f * expf(4.f * a * (a2 * a2));
	return c * (a2 * a2);
}

static float g_planetary_3D(float rho) {
	assert(rho >= 0 && "Rho should not be -ve");
	return rho < 1.f ? rho * rho * rho : 1.f;
}

static float zeta_planetary_3D(float rho) {
	assert(rho >= 0 && "Rho should not be -ve");
	return rho < 1.f ? 3.f : 0.f;
}

static void combined_planetary_3D(float rho, float* g, float* zeta) {
	assert(rho >= 0 && "Rho should not be -ve");
	*g = g_planetary_3D(rho);
	*zeta = zeta_planetary_3D(rho);
	return;
}

static float g_planetary_2D(float rho) {
	assert(rho >= 0 && "Rho should not be -ve");
	return rho < 1.f ? rho * rho : 1.f;
}

static float g_gaussian_3D(float rho) {
	/* = 1 to 8sf for rho ~>6. Taylor expansion otherwise */
	assert(rho >= 0 && "Rho should not be -ve");
	const float pi = 3.14159265359f;
	float ret;
	if (rho > 6.f) {
		ret = 1.f;
	}
	else {
		/* Approximate erf using Abramowitz and Stegan 1.7.26 */
		float a1 = 0.254829592f, a2 = -0.284496736, a3 = 1.421413741f;
		float a4 = -1.453152027f, a5 = 1.061405429f, p = 0.3275911f;
		float rho_sr2 = rho * RECIP_SQRTF_2;
		float t = 1.f / (1.f + p * rho_sr2);
		float t2 = t * t;	float t3 = t2 * t; float t4 = t2 * t2; float t5 = t3 * t2;
		float erf = 1.f - (a1 * t + a2 * t2 + a3 * t3 + a4 * t4 + a5 * t5) *
			expf(-rho_sr2 * rho_sr2);
		float term2 = rho * SQRTF_2_OVER_PI * expf(-rho_sr2 * rho_sr2);
		ret = erf - term2;
	}
	return ret;
}

static float zeta_gaussian_3D(float rho) {
	assert(rho >= 0 && "Rho should not be -ve");
	const float pi = 3.14159265359f;
	return SQRTF_2_OVER_PI * expf(-rho * rho * 0.5f);
}

static void combined_gaussian_3D(float rho, float* g, float* zeta) {
	assert(rho >= 0 && "Rho should not be -ve");
	*g = g_gaussian_3D(rho);
	*zeta = zeta_gaussian_3D(rho);
	return;
}

static float g_gaussian_2D(float rho) {
	assert(rho >= 0 && "Rho should not be -ve");
	return 1.f - expf(-rho * rho * 0.5f);
}

static float zeta_gaussian_2D(float rho) {
	assert(rho >= 0 && "Rho should not be -ve");
	return expf(-rho * rho * 0.5f);
}

CVTX_EXPORT const cvtx_VortFunc cvtx_VortFunc_singular(void)
{
	cvtx_VortFunc ret;
	ret.g_3D = &g_singular_3D;
	ret.g_2D = &g_singular_2D;
	ret.zeta_3D = &zeta_singular_3D;
	ret.eta_3D = &warn_bad_eta_fn;	/* Not possible for singular vortex */
	ret.eta_2D = &warn_bad_eta_fn;
	ret.combined_3D = &combined_singular_3D;
	strcpy(ret.cl_kernel_name_ext, "singular");
	return ret;
}

CVTX_EXPORT const cvtx_VortFunc cvtx_VortFunc_winckelmans(void)
{
	cvtx_VortFunc ret;
	ret.g_3D = &g_winckel_3D;
	ret.g_2D = &g_winckel_2D;
	ret.zeta_3D = &zeta_winckel_3D;
	ret.eta_3D = &eta_winckel_3D;
	ret.eta_2D = &eta_winckel_2D;
	ret.combined_3D = &combined_winckel_3D;
	strcpy(ret.cl_kernel_name_ext, "winckelmans");
	return ret;
}

CVTX_EXPORT const cvtx_VortFunc cvtx_VortFunc_planetary(void)
{
	cvtx_VortFunc ret;
	ret.g_3D = &g_planetary_3D;
	ret.g_2D = &g_planetary_2D;
	ret.zeta_3D = &zeta_planetary_3D;
	ret.eta_3D = &warn_bad_eta_fn; /* Not possible for planetary vortex */
	ret.eta_2D = &warn_bad_eta_fn;
	ret.combined_3D = &combined_planetary_3D;
	strcpy(ret.cl_kernel_name_ext, "planetary");
	return ret;
}

CVTX_EXPORT const cvtx_VortFunc cvtx_VortFunc_gaussian(void) {
	cvtx_VortFunc ret;
	ret.g_3D = &g_gaussian_3D;
	ret.g_2D = &g_gaussian_2D;
	ret.zeta_3D = &zeta_gaussian_3D;
	ret.eta_3D = &zeta_gaussian_3D;
	ret.eta_2D = &zeta_gaussian_2D;
	/* See Winckelmans et al., C. R. Physique 6 (2005), around eq (28) */
	ret.combined_3D = &combined_gaussian_3D;
	strcpy(ret.cl_kernel_name_ext, "gaussian");
	return ret;
}

