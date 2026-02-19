samplerate = 31250

is24bit = False

startnote = 27.5
amountnotes = 85

with open('phaseacctable.txt', 'w') as f:
  f.write(f'; Note to Phase Accumulator addition table for {amountnotes} notes, from {startnote}hz to {startnote* 2**((amountnotes-1)/12):.0f}hz\n')
  f.write(f'NOTE_TO_PHASE_ACC:\n')
  phaseaccarr = []
  for note in range(amountnotes):
    curfreq = startnote * 2**(note/12)
    if not is24bit:
      phaseacc = (curfreq / samplerate) * (2**16)
      phaseaccarr.append((round(phaseacc % 256), phaseacc // 256 % 256))
    else:
      phaseacc = (curfreq / samplerate) * (2**24)
      phaseaccarr.append((round(phaseacc % 256), phaseacc // 256 % 256, phaseacc // 65536))
  
  for i in range(0, len(phaseaccarr), 8):
    f.write(f'\tDT ')
    for j in range(0, 8):
      if i + j < len(phaseaccarr):
        if not is24bit:
          f.write(f'{phaseaccarr[i+j][0]:3g}, {phaseaccarr[i+j][1]:1g}')
        else:
          f.write(f'{phaseaccarr[i+j][0]:3g}, {phaseaccarr[i+j][1]:3g}, {phaseaccarr[i+j][2]:1g}')
        if j < 7 and (i+j != len(phaseaccarr)-1):
          f.write(', ')
    f.write(f'\n')