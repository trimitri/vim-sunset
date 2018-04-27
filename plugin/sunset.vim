" sunset.vim - Automatically set background on local sunrise/sunset time.
"
"  Maintainer: Alastair Touw <alastair@touw.me.uk>
"     Website: https://github.com/amdt/sunset
"     License: Distributed under the same terms as Vim. See ':help license'.
"     Version: 3.1.0
" Last Change: 2015-02-28
"       Usage: See 'doc/sunset.txt' or ':help sunset' if installed.
"
" Sunset follows the Semantic Versioning specification (http://semver.org).
"
" GetLatestVimScripts: 4277 22933 :AutoInstall: Sunset

let s:save_cpo = &cpo
set cpo&vim

" Clean up 'cpoptions' wherever this script should be terminated.
function! s:restore_cpoptions()
  let &cpo = s:save_cpo
  unlet s:save_cpo
endfunction

if exists('g:loaded_sunset')
  call s:restore_cpoptions()
  finish
endif
let g:loaded_sunset = 1

scriptencoding utf-8

let s:errors = []

if v:version < 703
  call add(s:errors, 'Requires Vim 7.3')
endif

if !has('float')
  call add(s:errors, 'Requires Vim be compiled with +float support.')
endif

if !exists('*strftime')
  call add(s:errors, 'Requires a system with strftime()')
endif

" Get the utc offset from the time zone offset
if !exists('g:sunset_utc_offset')
    let g:sunset_utc_offset = str2nr(strftime("%z")[:2])
endif

let s:required_options = ['g:sunset_latitude',
    \ 'g:sunset_longitude',
    \ 'g:sunset_utc_offset']

for option in s:required_options
  if exists(option)
    call filter(s:required_options, 'v:val != option')
  endif
endfor

if !empty(s:required_options)
  for option in s:required_options
    call add(s:errors, printf('%s missing! See '':help %s'' for more details.',
        \ option, option))
  endfor
endif

if !empty(s:errors)
  for error in s:errors
    echoerr error
  endfor
  call s:restore_cpoptions()
  finish
endif

let s:PI = 3.14159265359
let s:ZENITH = 90
let s:SUNRISE = 1
let s:SUNSET = 0
let s:CIVIL_TWILIGHT_DURATION = 30
lockvar s:PI
lockvar s:ZENITH
lockvar s:SUNRISE
lockvar s:SUNSET
lockvar s:CIVIL_TWILIGHT_DURATION

let s:DAYTIME_CHECKED = 0
let s:NIGHTTIME_CHECKED = 0

function! s:hours_and_minutes_to_minutes(hours, minutes)
  return (a:hours * 60) + a:minutes
endfunction

function! s:daytimep(current_time)
  if a:current_time <= (s:SUNRISE_TIME - (s:CIVIL_TWILIGHT_DURATION / 2))
      \ || a:current_time >= (s:SUNSET_TIME + (s:CIVIL_TWILIGHT_DURATION / 2))
    return 0
  else
    return 1
  endif
endfunction

" This algorithm for finding the local sunrise and sunset times published
" in the Almanac for Computers, 1990, by the Nautical Almanac Office of the
" United States Naval Observatory, as detailed
" here: http://williams.best.vwh.net/sunrise_sunset_algorithm.htm
function! s:calculate(sunrisep)
  function! s:degrees_to_radians(degrees)
    return (s:PI / 180) * a:degrees
  endfunction

  function! s:radians_to_degrees(radians)
    return (180 / s:PI) * a:radians
  endfunction

  function! s:minutes_from_decimal(number)
    return float2nr(60.0 / 100 * (a:number - floor(a:number)) * 100)
  endfunction

  " 1. First calculate the day of the year
  let l:day_of_year = strftime('%j')

  " 2. Convert the longitude to hour value and calculate an approximate time
  let l:longitude_hour = g:sunset_longitude / 15

  let l:n = a:sunrisep ? 6 : 18
  let l:approximate_time = l:day_of_year + ((l:n - l:longitude_hour) / 24)

  " 3. Calculate the Sun's mean anomaly
  let l:mean_anomaly = (0.9856 * l:approximate_time) - 3.289

  " 4. Calculate the Sun's true longitude
  let l:true_longitude = l:mean_anomaly
      \ + (1.916 * sin(s:degrees_to_radians(l:mean_anomaly)))
      \ + (0.020 * sin(s:degrees_to_radians(2)
      \ * s:degrees_to_radians(l:mean_anomaly)))
      \ + 282.634

  if l:true_longitude < 0
    let l:true_longitude = l:true_longitude + 360
  elseif l:true_longitude >= 360
    let l:true_longitude = l:true_longitude - 360
  endif

  " 5a. Calculate the Sun's right ascension
  let l:right_ascension = s:radians_to_degrees(atan(0.91764
      \ * tan(s:degrees_to_radians(l:true_longitude))))

  if l:right_ascension < 0
    let l:right_ascension = l:right_ascension + 360
  elseif l:right_ascension >= 360
    let l:right_ascension = l:right_ascension - 360
  endif

  " 5b. Right ascension value needs to be in the same quadrant as
  " l:true_longitude
  let l:true_longitude_quadrant = (floor(l:true_longitude / 90)) * 90
  let l:right_ascension_quadrant = (floor(l:right_ascension / 90)) * 90
  let l:right_ascension = l:right_ascension
      \ + (l:true_longitude_quadrant - l:right_ascension_quadrant)

  " 5c. Right ascension value needs to be converted into hours
  let l:right_ascension = l:right_ascension / 15

  " 6. Calculate the Sun's declination
  let l:sin_declination = 0.39782 * sin(s:degrees_to_radians(l:true_longitude))

  let l:cos_declination = cos(asin(s:degrees_to_radians(l:sin_declination)))

  " 7a. Calculate the Sun's local hour angle
  let l:cos_hour_angle = (cos(s:degrees_to_radians(s:ZENITH))
      \ - (l:sin_declination * sin(s:degrees_to_radians(g:sunset_latitude))))
      \ / (l:cos_declination * cos(s:degrees_to_radians(g:sunset_latitude)))

  " 7b. Finish calculating H and convert into hours
  if a:sunrisep
    let l:hour = 360 - s:radians_to_degrees(acos(l:cos_hour_angle))
  else
    let l:hour = s:radians_to_degrees(acos(l:cos_hour_angle))
  endif

  let l:hour = l:hour / 15

  " 8. Calculate local mean time of rising/setting
  let l:mean_time = l:hour
      \ + l:right_ascension
      \ - (0.06571 * l:approximate_time)
      \ - 6.622

  " 9. Adjust back to UTC
  let l:universal_time = l:mean_time - l:longitude_hour

  " 10. Convert l:universal_time value to local time zone of latitude/longitude
  let l:local_time = l:universal_time + g:sunset_utc_offset

  if l:local_time < 0
    let l:local_time = l:local_time + 24
  elseif l:local_time >= 24
    let l:local_time = l:local_time - 24
  endif

  return s:hours_and_minutes_to_minutes(float2nr(l:local_time),
      \ s:minutes_from_decimal(l:local_time))
endfunction

function! s:sunset()
  if s:daytimep(s:hours_and_minutes_to_minutes(strftime('%H'), strftime('%M')))
    if s:DAYTIME_CHECKED != 1
      if exists('*Sunset_daytime_callback')
        call Sunset_daytime_callback()
      else
        set background=light
      endif

      let s:DAYTIME_CHECKED = 1
      let s:NIGHTTIME_CHECKED = 0
    endif
  else
    if s:NIGHTTIME_CHECKED != 1
      if exists('*Sunset_nighttime_callback')
        call Sunset_nighttime_callback()
      else
        set background=dark
      endif

      let s:NIGHTTIME_CHECKED = 1
      let s:DAYTIME_CHECKED = 0
    endif
  endif
endfunction

let s:SUNRISE_TIME = s:calculate(s:SUNRISE)
let s:SUNSET_TIME = s:calculate(s:SUNSET)
call s:sunset()

autocmd CursorHold * nested call s:sunset()

call s:restore_cpoptions()

