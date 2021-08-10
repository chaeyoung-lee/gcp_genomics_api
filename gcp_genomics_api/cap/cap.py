import sys, glob

# read file
file = 'input/input{}.txt'.format(sys.argv[1])
text = open(file, 'r').read()
text = text.upper()

# output file
print(text)
output = 'output/output{}.txt'.format(sys.argv[1])
with open(output, 'w') as f:
	f.write(text)