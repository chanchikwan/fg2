;; Copyright (C) 2011,2012 Chi-kwan Chan
;; Copyright (C) 2011,2012 NORDITA
;;
;; This file is part of fg2.
;;
;; Fg2 is free software: you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; Fg2 is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with fg2.  If not, see <http://www.gnu.org/licenses/>.

pro vis, i, vorticity=vorticity, rtheta=rtheta, all=all, png=png

  if keyword_set(rtheta) and keyword_set(all) then begin
    print, '/rtheta and /all are incompatible; choose only one of them'
    return
  endif

  sz = get_screen_size()
  sz = (min(sz) / 512) * 512

  name = string(i, format='(i04)')
  print, 'Loading "' + name + '.raw"'
  data = load(name + '.raw')

  if keyword_set(png) then begin
    dsaved = !d.name
    set_plot, 'z'
    device, decompose=0, set_resolution=[sz, sz], set_pixel_depth=24
  endif else if !d.window eq -1 then begin
    window, xSize=sz, ySize=sz, retain=2
    device, decompose=0
  endif

  if keyword_set(all) then begin
    n = size(data.d) & n = n[3]
    psaved=!p.multi
    if n gt 1 then !p.multi=[0,2,(n-1)/2+1]
    x = data.x
    y = data.y
    for i = 0, n-1 do shade_surf, data.d[*,*,i], x, y, charsize=2
    !p.multi=psaved
  endif else begin
    dx = data.x[1] - data.x[0]
    if keyword_set(rtheta) then begin
      d = sp2c(data.d[*,*,0], size=sz)
      tvscl, reverse(d)
      tvscl, d, 1
    endif else begin
      if keyword_set(vorticity) then begin
        u1 = fft(data.d[*,*,1])
        u2 = fft(data.d[*,*,2])
        j  = getk(u1, /zeronyquist)
        w  = complex(0, j.k1) * u2 - complex(0, j.k2) * u1
        d  = real_part(fft(w, /inverse))
      endif else begin
        d  = data.d[*,*,0]
      endelse
      tvscl, congrid(d, sz, sz)
    endelse
  endelse

  if keyword_set(png) then begin
    write_png, name + '.png', tvrd(/true)
    set_plot, dsaved
  endif

end
