
type ventry = { v_ty: Ast.labeled_type }
type fentry = { f_ty: Ast.labeled_type; f_args: Ast.labeled_type list }

type entry =
  | VarEntry of ventry
  | LoopEntry of ventry
  | StaticVarEntry of ventry
  | FunEntry of fentry

type env = (string,entry) Hashtbl.t

val venv : env

val save_fn_ret_label : Ast.labeled_type -> string -> unit
val get_fn_ret_label : default:Ast.labeled_type -> string -> Ast.labeled_type

val update_label : string -> env -> Ast.label option -> Ast.labeled_type
val default_to_secret : env -> unit

val print_env : env -> unit
