"""
RVV-rollback is a tool to translate RISC-V
assembly code with Vector Extension version 1.0
to version 0.7
"""

__author__ = "Joseph Lee - EPCC (j.lee@epcc.ed.ac.uk)"
__version__ = "0.1.0"
__license__ = "MIT"

import argparse
import re


def replace_instruction(line, linenum, verbosity):
    newline = line
    if "_zve32f1p0_zve32x1p0_zvl32b1p0" in line:
        if verbosity > 0:
            print("Line number: {LINENUM}".format(LINENUM=linenum))
            print("original = " + line)
        newline = line.replace("_zve32f1p0_zve32x1p0_zvl32b1p0", "_v0p7")
        if verbosity > 0:
            print("updated  = " + newline)
            print("=========================================================")

        return newline

    

    dict_load_store_misc = {
        "vle32.v"    : "vlw.v",
        "vle16.v"    : "vlh.v",
        "vle8.v"     : "vlb.v",
        "vse32.v"    : "vsw.v",
        "vse16.v"    : "vsh.v",
        "vse8.v"     : "vsb.v",
        "vluxei32.v" : "vlxw.v",
        "vluxei16.v" : "vlxh.v",
        "vluxei8.v"  : "vlxb.v",
        "vsuxei32.v" : "vsuxw.v",
        "vsuxei16.v" : "vsuxh.v",
        "vsuxei8.v"  : "vsuxb.v",
        "vlse32.v"   : "vlsw.v",
        "vlse16.v"   : "vlsh.v",
        "vlse8.v"    : "vlsb.v",
        "vsse32.v"   : "vssw.v",
        "vsse16.v"   : "vssh.v",
        "vsse8.v"    : "vssb.v",
        "vloxei32.v" : "vlxw.v",
        "vloxei16.v" : "vlxh.v",
        "vloxei8.v"  : "vlxb.v",
        "vsoxei32.v" : "vsxw.v",
        "vsoxei16.v" : "vsxh.v",
        "vsoxei8.v"  : "vsxb.v",
        "vfncvt.xu.f.w": "vfncvt.xu.f.v",
        "vfncvt.x.f.w": "vfncvt.x.f.v",
        "vfncvt.f.xu.w": "vfncvt.f.xu.v",
        "vfncvt.f.x.w": "vfncvt.f.x.v",
        "vfncvt.f.f.w": "vfncvt.f.f.v"
    }

    for key in dict_load_store_misc:
        if (line.__contains__(key)):
            if verbosity > 0:
                print("Line number: {LINENUM}".format(LINENUM=linenum))
                print("original = " + line)
            newline = line.replace(key, dict_load_store_misc[key])
            if verbosity > 0:
                print("updated  = " + newline)
                print("=========================================================")
            return newline


        
    change_instruction_list = ["vsetvl", "vsetvli", "vsetivli",
                               "vl1r.v", "vl1re8.v", "vl1re16.v", "vl1re32", "vl1re64",
                               "vl2r.v", "vl2re8.v", "vl2re16.v", "vl2re32", "vl2re64",
                               "vl4r.v", "vl4re8.v", "vl4re16.v", "vl4re32", "vl4re64",
                               "vl8r.v", "vl8re8.v", "vl8re16.v", "vl8re32", "vl8re64",
                               "vs1r.v", "vs1re8.v", "vs1re16.v", "vs1re32", "vs1re64",
                               "vs2r.v", "vs2re8.v", "vs2re16.v", "vs2re32", "vs2re64",
                               "vs4r.v", "vs4re8.v", "vs4re16.v", "vs4re32", "vs4re64",
                               "vs8r.v", "vs8re8.v", "vs8re16.v", "vs8re32  ", "vs8re64",
                               "vzext.vf2", "vzext.vf4", "vzext.vf8",
                               "vsext.vf2", "vsext.vf4", "vsext.vf8"]
    
    if any(word in line for word in change_instruction_list):
        if verbosity > 0:
            print("Line number: {LINENUM}".format(LINENUM=linenum))
            print("original = " + line)
        instruction = re.split(r"[, \t]+", line.lstrip())
        

        match instruction[0]:
            # ===========================================================
            # VECTOR CONFIGURATION
            case "vsetvl" | "vsetvli":
                # disable tail/mask agnostic policy
                newline = line.replace("ta", "#ta")
                newline = newline.replace("tu", "#tu")
            case 'vsetivli':  # vsetivli rd, uimm, vtypei, tflag, mflag # rd = new vl, uimm = AVL (requested vector length), vtypei = new vtype setting
                rd  = instruction[1]
                avl = instruction[2]
                vtype = instruction[3]
                mtype = instruction[4]
                # safer copy temporary register t0 to memory
                """ line = ("sd     t0, 0(sp)\n" +  # copy temporary register t0 to stack
                        "addi   t0, {AVL}\n" +  # use t0 to store intermediate val
                        "vsetvli  {RD}, t0, {VTYPE}, {MTYPE}\n" + # configure vector
                        "ld     t0, 0(sp)\n")  # copy from stack back to t0
                newline = line.format(AVL = avl, RD = rd, VTYPE = vtype, MTYPE = mtype) """
                # unsafe use t0
                newline = ("\taddi   t0, {AVL}\n" +
                        "\tvsetvli  {RD}, t0, {VTYPE}, {MTYPE}\n")
                newline = newline.format(
                    AVL=avl, RD=rd, VTYPE=vtype, MTYPE=mtype)
            # ===========================================================


            # WHOLE REGISTER LOAD/STORE: Currently do not backup t0, t1 before using, unsafe
            case 'vl1r.v' | 'vl1re8.v' | 'vl1re16.v' | 'vl1re32' | 'vl1re64':
                rd = instruction[1]
                rs = instruction[2]
                if(instruction[3]):
                    vm = instruction[3]
                else:
                    vm = ""
                newline = ("\tcsrr     t0, vl\n" +
                        "\tcsrr     t1, vtype\n" +
                        "\tvsetvli  x0, x0, e32, m1\n" +  # Set LMUL = 1
                        "\tvlw.v    {RD}, {RS} {VM}\n" +
                        "\tvsetvl   x0, t0, t1\n")
                newline = newline.format(RD=rd, RS=rs, VM=(","+vm))
            case 'vl2r.v' | 'vl2re8.v' | 'vl2re16.v' | 'vl2re32' | 'vl2re64':
                rd = instruction[1]
                rs = instruction[2]
                if (instruction[3]):
                    vm = instruction[3]
                else:
                    vm = ""
                newline = ("\tcsrr     t0, vl\n" +
                        "\tcsrr     t1, vtype\n" +
                        "\tvsetvli  x0, x0, e32, m2\n" +  # Set LMUL = 2
                        "\tvlw.v    {RD}, {RS} {VM}\n" +
                        "\tvsetvl   x0, t0, t1\n")
                newline = line.format(RD=rd, RS=rs, VM=(","+vm))

            case 'vl4r.v' | 'vl4re8.v' | 'vl4re16.v' | 'vl4re32' | 'vl4re64':
                rd = instruction[1]
                rs = instruction[2]
                if (instruction[3]):
                    vm = instruction[3]
                else:
                    vm = ""
                newline = ("\tcsrr     t0, vl\n" +
                        "\tcsrr     t1, vtype\n" +
                        "\tvsetvli  x0, x0, e32, m4\n" +  # Set LMUL = 4
                        "\tvlw.v    {RD}, {RS} {VM}\n" +
                        "\tvsetvl   x0, t0, t1\n")
                newline = newline.format(RD=rd, RS=rs, VM=(","+vm))

            case 'vl8r.v' | 'vl8re8.v' | 'vl8re16.v' | 'vl8re32' | 'vl8re64':
                rd = instruction[1]
                rs = instruction[2]
                if (instruction[3]):
                    vm = instruction[3]
                else:
                    vm = ""
                newline = ("\tcsrr     t0, vl\n" +
                        "\tcsrr     t1, vtype\n" +
                        "\tvsetvli  x0, x0, e32, m8\n" +  # Set LMUL = 8
                        "\tvlw.v    {RD}, {RS} {VM}\n" +
                        "\tvsetvl   x0, t0, t1\n")
                newline = newline.format(RD=rd, RS=rs, VM=(","+vm))

            case 'vs1r.v' | 'vs1re8.v' | 'vs1re16.v' | 'vs1re32' | 'vs1re64':
                rd = instruction[1]
                rs = instruction[2]
                if (instruction[3]):
                    vm = instruction[3]
                else:
                    vm = ""
                newline = ("\tcsrr     t0, vl\n" +
                        "\tcsrr     t1, vtype\n" +
                        "\tvsetvli  x0, x0, e32, m1\n" +  # Set LMUL = 1
                        "\tvsw.v    {RD}, {RS} {VM}\n" +
                        "\tvsetvl   x0, t0, t1\n")
                newline = newline.format(RD=rd, RS=rs, VM=(","+vm))

            case 'vs2r.v' | 'vs2re8.v' | 'vs2re16.v' | 'vs2re32' | 'vs2re64':
                rd = instruction[1]
                rs = instruction[2]
                if (instruction[3]):
                    vm = instruction[3]
                else:
                    vm = ""
                newline = ("\tcsrr     t0, vl\n" +
                        "\tcsrr     t1, vtype\n" +
                        "\tvsetvli  x0, x0, e32, m2\n" +  # Set LMUL = 2
                        "\tvsw.v    {RD}, {RS} {VM}\n" +
                        "\tvsetvl   x0, t0, t1\n")
                newline = newline.format(RD=rd, RS=rs, VM=(","+vm))

            case 'vs4r.v' | 'vs4re8.v' | 'vs4re16.v' | 'vs4re32' | 'vs4re64':
                rd = instruction[1]
                rs = instruction[2]
                if (instruction[3]):
                    vm = instruction[3]
                else:
                    vm = ""
                newline = ("\tcsrr     t0, vl\n" +
                        "\tcsrr     t1, vtype\n" +
                        "\tvsetvli  x0, x0, e32, m4\n" +  # Set LMUL = 4
                        "\tvsw.v    {RD}, {RS} {VM}\n" +
                        "\tvsetvl   x0, t0, t1\n")
                newline = newline.format(RD=rd, RS=rs, VM=(","+vm))

            case 'vs8r.v' | 'vs8re8.v' | 'vs8re16.v' | 'vs8re32' | 'vs8re64':
                rd = instruction[1]
                rs = instruction[2]
                if (instruction[3]):
                    vm = instruction[3]
                else:
                    vm = ""
                newline = ("\tcsrr     t0, vl\n" +
                        "\tcsrr     t1, vtype\n" +
                        "\tvsetvli  x0, x0, e32, m8\n" +  # Set LMUL = 8
                        "\tvsw.v    {RD}, {RS} {VM}\n" +
                        "\tvsetvl   x0, t0, t1\n")
                newline = newline.format(RD=rd, RS=rs, VM=(","+vm))

            # ===========================================================

            # VECTOR INTEGER ZERO/SIGN EXTENSION
            case 'vzext.vf2':  # zero extend vzext.v vd, vs2, vm
                vd = instruction[1]
                vs2 = instruction[2]
                if instruction[3]:
                    vm = instruction[3]
                else:
                    vm = ""
                newline = "\tvwaddu.vx, {VD}, {VS2}, x0 {VM}\n" # unsigned widening add zero
                newline = newline.format(VD=vd, VS2=vs2, VM=(","+vm))

            case 'vzext.vf4':
                vd = instruction[1]
                vs2 = instruction[2]
                if instruction[3]:
                    vm = instruction[3]
                else:
                    vm = ""
                newline = ("\tvwaddu.vx, {VD}, {VS2}, x0 {VM}\n" +
                        "\tvwaddu.vx, {VD}, {VD},  x0 {VM}\n")  # unsigned widening add zero twice
                newline = newline.format(VD=vd, VS2=vs2, VM=(","+vm))
            case 'vzext.vf8':
                vd = instruction[1]
                vs2 = instruction[2]
                if instruction[3]:
                    vm = instruction[3]
                else:
                    vm = ""
                newline = ("\tvwaddu.vx, {VD}, {VS2}, x0 {VM}\n" +
                        "\tvwaddu.vx, {VD}, {VD},  x0 {VM}\n" +
                        "\tvwaddu.vx, {VD}, {VD},  x0 {VM}\n")  # unsigned widening add zero three times
                newline = newline.format(VD=vd, VS2=vs2, VM=(","+vm))

            case 'vsext.vf2':  # sign extend vsext.v vd, vs2, vm
                vd = instruction[1]
                vs2 = instruction[2]
                if instruction[3]:
                    vm = instruction[3]
                else:
                    vm = ""
                newline = "\tvwadd.vx, {VD}, {VS2}, x0 {VM}\n"  # signed widening add zero
                newline = newline.format(VD=vd, VS2=vs2, VM=(","+vm))

            case 'vsext.vf4':
                vd = instruction[1]
                vs2 = instruction[2]
                if instruction[3]:
                    vm = instruction[3]
                else:
                    vm = ""
                newline = ("\tvwadd.vx, {VD}, {VS2}, x0 {VM}\n" +
                        "\tvwadd.vx, {VD}, {VD},  x0 {VM}\n")  # signed widening add zero twice
                newline = newline.format(VD=vd, VS2=vs2, VM=(","+vm))
            case 'vsext.vf8':
                vd = instruction[1]
                vs2 = instruction[2]
                if instruction[3]:
                    vm = instruction[3]
                else:
                    vm = ""
                newline = ("\tvwadd.vx, {VD}, {VS2}, x0 {VM}\n" +
                        "\tvwadd.vx, {VD}, {VD},  x0 {VM}\n" +
                        "\tvwadd.vx, {VD}, {VD},  x0 {VM}\n")  # signed widening add zero three times
                newline = newline.format(VD=vd, VS2=vs2, VM=(","+vm))
        if verbosity > 0:
            print("updated  = " + newline)
            print("=========================================================")

    return newline
        





def main(args):
    filename = args.filename
    if (args.outfile):
        outfilename = args.outfile
    else:
        outfilename = filename.replace(".s", "-rvv0p7.s")

    print("input file = {IN}  |  output file = {OUT}".format(IN=filename, OUT=outfilename))

    file = open(filename, 'r')
    outfile = open(outfilename, 'w')

    linenum = 0
    for line in file.readlines():
        linenum = linenum + 1
        newline = replace_instruction(line, linenum, args.verbose)
        outfile.writelines(newline)


    file.close()
    outfile.close()










if __name__ == "__main__":
    parser = argparse.ArgumentParser()

    parser.add_argument("filename", help="Required filename")

    parser.add_argument("-o", "--outfile", action="store", dest="outfile")

    # Optional verbosity counter (eg. -v, -vv, -vvv, etc.)
    parser.add_argument(
        "-v",
        "--verbose",
        action="count",
        default=0,
        help="Verbosity (-v, -vv, etc)")

    # Specify output of "--version"
    parser.add_argument(
        "--version",
        action="version",
        version="%(prog)s (version {version})".format(version=__version__))

    args = parser.parse_args()
    main(args)
