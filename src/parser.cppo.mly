%{
open Lexing
open Pos
open Err
open Ast

let to_type { data=t; pos=p } =
  match t with
    | "bool" -> Bool
    | "int8" -> Int 8
    | "int16" -> Int 16
    | "int32" -> Int 32
    | "int64" -> Int 64
    | "uint8" -> UInt 8
    | "uint16" -> UInt 16
    | "uint32" -> UInt 32
    | "uint64" -> UInt 64
    | "uint128" -> UInt 128
    | _ as t -> raise (errParseType p t)
%}

%token <int> INT
%token <bool> BOOL
%token <string> STRING
%token VOID
%token PLUS MINUS TIMES DIVIDE MODULO
%token EQUAL NEQUAL GREATERTHAN GREATERTHANEQ LESSTHAN LESSTHANEQ
%token LOGNOT LOGAND LOGOR
%token BITOR BITXOR BITAND LEFTSHIFT RIGHTSHIFT BITNOT
%token ASSIGN
%token PLUSEQ MINUSEQ TIMESEQ DIVIDEEQ MODULOEQ
%token LOGANDEQ LOGOREQ
%token BITOREQ BITXOREQ BITANDEQ LEFTSHIFTEQ RIGHTSHIFTEQ
%token QUESTION COLON
%token LPAREN RPAREN

%token IF ELSE
%token <string> IDENT
%token <string> TYPE
%token FOR TO
%token LBRACK RBRACK
%token LBRACE RBRACE

%token SECRET PUBLIC
%token CONST MUT
%token REF
%token RETURN
%token DECLASSIFY
%token ARRZEROS ARRCOPY ARRVIEW
%token SEMICOLON
%token COMMA
%token LEN RIGHTARROW
%token EXTERN

%token FD_START ST_START EX_START EX_END

%token EOF

(* precedence based on C operator precedence
 * http://en.cppreference.com/w/c/language/operator_precedence *)
%left QUESTION
%left LOGOR
%left LOGAND
%left BITOR
%left BITXOR
%left BITAND
%left EQUAL NEQUAL
%left GREATERTHAN GREATERTHANEQ LESSTHAN LESSTHANEQ
%left LEFTSHIFT RIGHTSHIFT
%left PLUS MINUS
%left TIMES DIVIDE MODULO
%nonassoc UNARYOP

(* Preprocessor shenanigans *)
#define mkpos make_pos $symbolstartpos $endpos
#define mkposof(x) make_pos $startpos(x) $endpos(x)
#define mkposrange(x,y) make_pos $startpos(x) $endpos(y)

%start <Ast.fact_module> main
%start <Ast.top_level> top_level

%%
main:
  | fact_module EOF { $1 }

%inline paren(X):
  | LPAREN x=X RPAREN { x }

%inline brack(X):
  | LBRACK x=X RBRACK { x }

%inline plist(X):
  | LPAREN xs=separated_list(COMMA, X) RPAREN { xs }

%inline blist(X):
  | LBRACE xs=list(X) RBRACE { xs }

%inline alist(X):
  | LBRACE xs=separated_list(COMMA, X) RBRACE { xs }

var_name:
  | x=IDENT { mkpos x }

fun_name:
  | f=IDENT { mkpos f }

base_type:
  | t=TYPE { mkpos (to_type (mkpos t)) }

array_type:
  | b=base_type l=brack(lexpr) { mkpos (ArrayAT(b, l)) }
  | b=base_type LBRACK RBRACK { mkpos (ArrayAT(b, mkpos LUnspecified)) }

label:
  | PUBLIC { mkpos Public }
  | SECRET { mkpos Secret }

mutability:
  | CONST { mkpos Const }
  | MUT { mkpos Mut }

unop:
  | MINUS { Neg }
  | LOGNOT { LogicalNot }
  | BITNOT { BitwiseNot }

%inline binop:
  | PLUS { Plus }
  | MINUS { Minus }
  | TIMES { Multiply }
  | DIVIDE { Divide }
  | MODULO { Modulo }
  | EQUAL { Equal }
  | NEQUAL { NEqual }
  | GREATERTHAN { GT }
  | GREATERTHANEQ { GTE }
  | LESSTHAN { LT }
  | LESSTHANEQ { LTE }
  | LOGAND { LogicalAnd }
  | LOGOR { LogicalOr }
  | BITOR { BitwiseOr }
  | BITXOR { BitwiseXor }
  | BITAND { BitwiseAnd }
  | LEFTSHIFT { LeftShift }
  | RIGHTSHIFT { RightShift }

%inline binopeq:
  | PLUSEQ { Plus }
  | MINUSEQ { Minus }
  | TIMESEQ { Multiply }
  | DIVIDEEQ { Divide }
  | MODULOEQ { Modulo }
  | LOGANDEQ { LogicalAnd }
  | LOGOREQ { LogicalOr }
  | BITOREQ { BitwiseOr }
  | BITXOREQ { BitwiseXor }
  | BITANDEQ { BitwiseAnd }
  | LEFTSHIFTEQ { LeftShift }
  | RIGHTSHIFTEQ { RightShift }

arg:
  | e=expr { mkpos (ByValue e) }
  | REF x=var_name { mkpos (ByRef x) }
  | hasmut=boption(REF) a=array_expr { mkpos (ByArray(a,mkpos (if hasmut then Mut else Const))) }

lexpr:
  | e=expr { mkpos (LExpression e) }

expr:
  | e=paren(expr) { mkpos e.data }
  | b=BOOL { mkpos (if b then True else False) }
  | n=INT { mkpos (IntLiteral n) }
  | s=STRING {mkpos (StringLiteral s) }
  | x=var_name { mkpos (Variable x) }
  | a=var_name e=brack(expr) { mkpos (ArrayGet(a, e)) }
  | LEN a=var_name { mkpos (ArrayLen a) }
  | b=paren(base_type) e=expr { mkpos (IntCast(b, e)) }
  | op=unop e=expr %prec UNARYOP { mkpos (UnOp(op, e)) }
  | e1=expr op=binop e2=expr { mkpos (BinOp(op, e1, e2)) }
  | e1=expr QUESTION e2=expr COLON e3=expr { mkpos (TernOp(e1, e2, e3)) }
  | fn=fun_name args=plist(arg) { mkpos (FnCall(fn, args)) }
  | DECLASSIFY e=paren(expr) { mkpos (Declassify e) }

array_expr:
  | es=alist(expr) { mkpos (ArrayLit es) }
  | a=var_name { mkpos (ArrayVar a) }
  | ARRZEROS l=paren(lexpr) { mkpos (ArrayZeros l) }
  | ARRCOPY a=paren(var_name) { mkpos (ArrayCopy a) }
  | ARRVIEW LPAREN a=var_name COMMA i=expr COMMA l=lexpr RPAREN { mkpos (ArrayView(a, i, l)) }

base_variable_type:
  | b=base_type
    { mkpos (RefVT(b, mkpos Unknown, mkpos Const)) }
  | l=label b=base_type
    { mkpos (RefVT(b, l, mkpos Const)) }
  | m=mutability b=base_type
    { mkpos (RefVT(b, mkpos Unknown, m)) }
  | l=label m=mutability b=base_type
    { mkpos (RefVT(b, l, m)) }

array_variable_type:
  | a=array_type
    { mkpos (ArrayVT(a, mkpos Unknown, mkpos Const)) }
  | l=label a=array_type
    { mkpos (ArrayVT(a, l, mkpos Const)) }
  | m=mutability a=array_type
    { mkpos (ArrayVT(a, mkpos Unknown, m)) }
  | l=label m=mutability a=array_type
    { mkpos (ArrayVT(a, l, m)) }

%inline if_clause:
  | IF c=paren(expr) thens=block elses=loption(ELSE elses=else_clause { elses })
    { mkpos (If(c, thens, elses)) }

else_clause:
  | iff=if_clause
    { [iff] }
  | elses=block
    { elses }

statement:
  | b=base_variable_type x=var_name ASSIGN e=expr SEMICOLON
    { mkpos (BaseDec(x, b, e)) }
  | a=array_variable_type x=var_name ASSIGN ae=array_expr SEMICOLON
    { mkpos (ArrayDec(x, a, ae)) }
  | a=array_variable_type x=var_name ASSIGN n=var_name RIGHTARROW e=expr SEMICOLON
    { let { data=ArrayVT({ data=ArrayAT(b, l) }, _, _) } = a in
      mkpos (ArrayDec(x, a, mkposrange(n,e) (ArrayComp(b, l, n, e)))) }
  | x=var_name ASSIGN e=expr SEMICOLON
    { mkpos (BaseAssign(x, e)) }
  | x=var_name op=binopeq e=expr SEMICOLON
    { mkpos (BaseAssign(x, mkpos (BinOp(op, mkposof(x) (Variable x), e)))) }
  | a=var_name i=brack(expr) ASSIGN e=expr SEMICOLON
    { mkpos (ArrayAssign(a, i, e)) }
  | a=var_name i=brack(expr) op=binopeq e=expr SEMICOLON
    { mkpos (ArrayAssign(a, i, mkpos (BinOp(op, mkposrange(a,i) (ArrayGet(a, i)), e)))) }
  | iff=if_clause (* takes care of else ifs and elses too! *)
    { iff }
  | a=FOR LPAREN b=base_type i=var_name ASSIGN e1=expr TO e2=expr z=RPAREN stms=block
    { mkposrange(a,z) (For(i, b, e1, e2, stms)) }
  | fn=fun_name args=plist(arg) SEMICOLON
    { mkpos (VoidFnCall(fn, args)) }
  | RETURN e=expr SEMICOLON
    { mkpos (Return e) }
  | RETURN SEMICOLON
    { mkpos VoidReturn }

%inline block: xs=blist(statement) { xs }

ret_type:
  | VOID { None }
  | l=label b=base_type { Some (mkpos (BaseET(b, l))) }

param_type:
  | l=label b=base_type
    { mkpos (RefVT(b, l, mkpos Const)) }
  | l=label m=mutability b=base_type
    { mkpos (RefVT(b, l, m)) }
  | l=label a=array_type
    { mkpos (ArrayVT(a, l, mkpos Const)) }
  | l=label m=mutability a=array_type
    { mkpos (ArrayVT(a, l, m)) }

param:
  | t=param_type x=var_name
    { mkpos (Param(x, t)) }

function_dec:
  | r=ret_type fn=fun_name params=plist(param) body=block
    { mkpos (FunDec(fn, r, params, body)) }
  | EXTERN r=ret_type fn=fun_name params=plist(param) SEMICOLON
    { mkpos (CExtern(fn, r, params)) }

fact_module:
  | fdecs=nonempty_list(function_dec)
    { Module fdecs }

top_level:
  | FD_START fd=function_dec       { FunctionDec fd }
  | ST_START st=statement          { Statement st }
  | EX_START ex=expr EX_END        { Expression ex }
