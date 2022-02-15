import std.stdio;
import SymbolTable;
import Expr;
import Parser;

class Node {
    protected Node left, right;
    static protected SymbolTable symtab;
    this() {
        left = right = null;
    }
    this(Node l, Node r) {
        left = l;
        right = r;
    }
    this(SymbolTable s) {
        symtab = s;
        left = right = null;
    }
    final ref Node link(Node n) { // must return ref
        if (right) {
            throw new Exception("cannot link");
        }
        right = n;
        return right;
    }
    final void linkLast(Node n) {
        auto last = this;
        while (last.right !is null) {
            last = last.right;
        }
        last.right = n;
    }
    final void prelude() {
        writeln("\t.section .mixed, \"awx\"");
        writeln("\t.global basic_run");
        writeln("\t.arch armv2");
        writeln("\t.syntax unified");
        writeln("\t.arm");
        writeln("\t.fpu vfp");
        writeln("\t.type    basic_run, %function");
        writeln("basic_run:");
        // r4 = RETURN address, r5 = index for LetDim
        writeln("\tpush\t{r4, lr}");
        writeln("\tmov\tr4, #0");
        //writeln("\tmov\tr5, #0");
    }
    final void interlude() {
        writeln(".basic_end:");
        writeln("\tmov\tr0, #0");
        writeln("\tpop\t{r4, pc}");
        writeln("\t.balign 8");
    }
    void codegen() {
        if (right) {
            right.codegen();
        }
    }
}

class Line : Node {
    private ushort line;
    this(ushort l) {
        line = l;
    }
    override void codegen() {
        symtab.setLine(line, false);
        if (symtab.referencedLine(line)) {
            writeln(".", line, ":");
        }
        super.codegen();
    }
}

class Stop : Node {
    override void codegen() {
        writeln("\tb\t.basic_end");
        super.codegen();
    }
}

class Goto : Node {
    private ushort line;
    this(ushort l) {
        line = l;
    }
    override void codegen() {
        assert(symtab.referencedLine(line));
        writeln("\tb\t.", line);
        super.codegen();
    }
}

class GoSub : Node {
    private ushort line;
    this(ushort l) {
        line = l;
    }
    override void codegen() {
        assert(symtab.referencedLine(line));
        writeln("\tcmp\tr4, #0");
        writeln("\tmovne\tr0, #2"); // error: already in GOSUB
        writeln("\tmovne\tr1, #", symtab.line & 0xff00);
        writeln("\torrne\tr1, r1, #", symtab.line & 0xff);
        writeln("\tbne\truntime_error(PLT)");
        writeln("\tmov\tr4, pc");
        writeln("\tb\t.", line);
        writeln("\tnop"); // for some armv3
        writeln("\tmov\tr4, #0");
        super.codegen();
    }
}

class Return : Node {
    override void codegen() {
        writeln("\tcmp\tr4, #0");
        writeln("\tmoveq\tr0, #3"); // error: not in GOSUB
        writeln("\tmoveq\tr1, #", symtab.line & 0xff00);
        writeln("\torreq\tr1, r1, #", symtab.line & 0xff);
        writeln("\tbeq\truntime_error(PLT)");
        writeln("\tmov\tpc, r4");
        super.codegen();
    }
}

class Let : Node {
    private int ident;
    this(int i, Expr e) {
        ident = i;
        symtab.initializeID(ident);
        left = e;
    }
    override void codegen() {
        Expr.Expr.clearRegs();
        left.codegen();
        writeln("\tadrl\tr0, .", symtab.getID(ident));
        writeln("\tvstr.f64\td", (cast(Expr)left).result, ", [r0]");
        super.codegen();
    }
}

class LetDim : Node {
    private int ident;
    this(int i, Expr idx, Expr e) {
        ident = i;
        symtab.initializeID(ident);
        symtab.initializeDIM(ident);
        left = new Node(idx, e);
    }
    override void codegen() {
        Expr.Expr.clearRegs();
        left.left.codegen();
        writeln("\tvcvt.s32.f64\ts0, d", (cast(Expr)(left.left)).result);
        writeln("\tvmov\tr0, s0");
        writeln("\tadrl\tr1, ._size", symtab.getID(ident));
        writeln("\tldr\tr1, [r1]");
        writeln("\tcmp\tr0, r1");
        writeln("\tmovgt\tr0, #4"); // error: index out of bounds
        writeln("\tmovgt\tr1, #", symtab.line & 0xff00);
        writeln("\torrgt\tr1, r1, #", symtab.line & 0xff);
        writeln("\tbgt\truntime_error(PLT)");
        writeln("\tpush\t{r0}");
        Expr.Expr.clearRegs();
        left.right.codegen();
        writeln("\tpop\t{r0}");
        writeln("\tadrl\tr1, ._data", symtab.getID(ident));
        writeln("\tadd\tr0, r1, r0, LSL #3");
        writeln("\tvstr.f64\td", (cast(Expr)(left.right)).result, ", [r0]");
        super.codegen();
    }
}

class Read : Node {
    private int ident;
    this(int i) {
        ident = i;
        symtab.initializeID(ident);
    }
    override void codegen() {
        writeln("\tadrl\tr0, ._data_ptr");
        writeln("\tadrl\tr1, ._data_max");
        writeln("\tldr\tr2, [r0]");
        writeln("\tldr\tr3, [r1]");
        writeln("\tcmp\tr2, r3");
        writeln("\tmovge\tr0, #1"); // error: out of data
        writeln("\tmovge\tr1, #", symtab.line & 0xff00);
        writeln("\torrge\tr1, r1, #", symtab.line & 0xff);
        writeln("\tbge\truntime_error(PLT)");
        writeln("\tadrl\tr3, ._data");
        writeln("\tadd\tr3, r3, r2, LSL #3");
        writeln("\tvldr.f64\td0, [r3]");
        writeln("\tadd\tr2, r2, #1");
        writeln("\tstr\tr2, [r0]");
        writeln("\tadrl\tr0, .", symtab.getID(ident));
        writeln("\tvstr.f64\td0, [r0]");
        super.codegen();
    }
}

class Input : Node {
    private int ident;
    this(int i) {
        ident = i;
        symtab.initializeID(ident);
    }
    override void codegen() {
        writeln("\tadrl\tr0, .", symtab.getID(ident));
        writeln("\tbl\tread_number(PLT)");
        super.codegen();
    }
}

class If : Node {
    private ushort line;
    private int relop, lhs, rhs;
    this(Expr l, int op, Expr r, ushort n) {
        left = new Node(l, r);
        relop = op;
        line = n;
        symtab.registerFlow(line);
    }
    override void codegen() {
        assert(symtab.referencedLine(line));
        Expr.Expr.clearRegs();
        left.left.codegen();
        left.right.codegen();
        writeln("\tvcmp.f64\td", (cast(Expr)left.left).result, ", d", (cast(Expr)left.right).result);
        writeln("\tvmrs\tAPSR_nzcv, FPSCR");
        switch (relop) {
            case TokenKind.EQ:
                writeln("\tbeq\t.", line);
                break;
            case TokenKind.NE:
                writeln("\tbne\t.", line);
                break;
            case TokenKind.LT:
                writeln("\tblt\t.", line);
                break;
            case TokenKind.LE:
                writeln("\tble\t.", line);
                break;
            case TokenKind.GE:
                writeln("\tbge\t.", line);
                break;
            case TokenKind.GT:
                writeln("\tbgt\t.", line);
                break;
            default:
                throw new Exception("bad relop");
        }
        super.codegen();
    }
}

class For : Node {
    private int ident, id;
    private static int[] stack, ident_stack;
    private static int for_id = -1;
    static int pop() {
        if (stack.length == 0) {
            return -1;
        }
        int id = stack[$ - 1];
        stack = stack[0 .. $ - 1];
        return id;
    }
    static int popID() {
        if (ident_stack.length == 0) {
            return -1;
        }
        int id = ident_stack[$ - 1];
        ident_stack = ident_stack[0 .. $ - 1];
        return id;
    }
    this(int i, Expr b, Expr e, Expr s = null) {
        left = new Node(new Node(b, e), s);
        ident = i;
        symtab.initializeID(ident);
        id = ++for_id;
        stack ~= for_id;
        ident_stack ~= ident;
    }
    override void codegen() {
        Expr.Expr.clearRegs();
        left.left.left.codegen();
        writeln("\tadrl\tr0, .", symtab.getID(ident));
        writeln("\tvstr.f64\td", (cast(Expr)(left.left.left)).result, ", [r0]");
        writeln("\tb\t._for_loop", id);
        writeln("._for_incr", id, ":");
        writeln("\tadrl\tr0, .", symtab.getID(ident));
        writeln("\tvldr.f64\td0, [r0]");
        if (left.right is null) {
            writeln("\tadrl\tr1, ._1");
            writeln("\tvldr.f64\td1, [r1]");
            writeln("\tvadd.f64\td0, d0, d1");
            Expr.Expr.clearRegs();
            left.left.right.codegen();
            writeln("\tvcmp.f64\td0, d", (cast(Expr)(left.left.right)).result);
        }
        else {
            Expr.Expr.clearRegs();
            left.right.codegen();
            writeln("\tvmov.f64\td1, d", (cast(Expr)(left.right)).result);
            writeln("\tvadd.f64\td0, d0, d1");
            Expr.Expr.clearRegs();
            left.left.right.codegen();
            writeln("\tvcmp.f64\td1, #0.0");
            writeln("\tvmrs\tAPSR_nzcv, FPSCR");
            writeln("\tvcmpgt.f64\td0, d", (cast(Expr)(left.left.right)).result);
            writeln("\tvcmplt.f64\td", (cast(Expr)(left.left.right)).result, ", d0");
        }
        writeln("\tvmrs\tAPSR_nzcv, FPSCR");
        writeln("\tbgt\t._for_end", id);
        writeln("\tadrl\tr0, .", symtab.getID(ident));
        writeln("\tvstr.f64\td0, [r0]");
        writeln("._for_loop", id, ":");
        super.codegen();
    }
}

class Next : Node {
    private int for_id;
    this(int id) {
        for_id = For.pop();
        if (for_id == -1) {
            symtab.error("NEXT WITHOUT FOR");
        }
        if (id != For.popID()) {
            symtab.error("INVALID NEXT VARIABLE");
        }
    }
    override void codegen() {
        writeln("\tb\t._for_incr", for_id);
        writeln("._for_end", for_id, ":");
        super.codegen();
    }
}