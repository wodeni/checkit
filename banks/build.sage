# path to bank containing __bank__.xml and *.sage/*.ptx files
bank = "nimo-vis"
# bank = "tbil-la"

# Generate the bank
oldwd=os.getcwd()
try: os.chdir(".."); load("main.sage")
finally: os.chdir(oldwd)
    
build_bank(bank,amount=50,public=True,fixed=True)

