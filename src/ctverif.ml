open Llvm
open Tast
open Pos

exception CTVerifError

type t =
  | ASSUME
  | PUBLIC_IN
  | PUBLIC_OUT
  | DECLASSIFIED_OUT
  | SMACK_VALUE
  | SMACK_VALUES
  | SMACK_RETURN_VALUE

let string_of_ct_verif = function
  | ASSUME -> "__VERIFIER_assume"
  | PUBLIC_IN -> "public_in"
  | PUBLIC_OUT -> "public_out"
  | DECLASSIFIED_OUT -> "declassified_out"
  | SMACK_VALUE -> "__SMACK_value"
  | SMACK_VALUES -> "__SMACK_values"
  | SMACK_RETURN_VALUE -> "__SMACK_return_value"

let smack_ty = ref None

(* Todo: throw this into a type environment so that it can be reused *)
let smack_struct ctx llmod =
  let str = named_struct_type ctx "struct.smack_value" in
  let pt = pointer_type (i8_type ctx) in
  struct_set_body str [| pt |] false; (* TODO: what should the packing be?*)
  str

let get_smack_ty llctx llmod =
  match !smack_ty with
    | None ->
      let st = pointer_type (smack_struct llctx llmod) in
      smack_ty := Some st;
      st
    | Some st -> st

(* Target dependent attributes. These are for x86-64. We need to explore
   this more if we want to support more architectures *)
let set_attributes f =
  add_target_dependent_function_attr f "less-precise-fpmad" "false";
  add_target_dependent_function_attr f "no-frame-pointer-elim" "true";
  add_target_dependent_function_attr f "no-frame-pointer-elim-non-leaf" "";
  add_target_dependent_function_attr f "no-infs-fp-math" "false";
  add_target_dependent_function_attr f "no-nans-fp-math" "false";
  add_target_dependent_function_attr f "stack-protector-buffer-size" "8";
  add_target_dependent_function_attr f "target-cpu" "x86-64";
  add_target_dependent_function_attr f "target-features" "+fxsr,+mmx,+sse,+sse2";
  add_target_dependent_function_attr f "unsafe-fp-math" "false";
  add_target_dependent_function_attr f "use-soft-float" "false";
  add_target_dependent_function_attr f "disable-tail-calls" "false"

let declare_ct_verif llctx llmod = function
  | ASSUME ->
    let i32_ty = i32_type llctx in
    let vt = void_type llctx in
    let arg_types = [| i32_ty |] in
    let ft = function_type vt arg_types in
    let f = declare_function (string_of_ct_verif ASSUME) ft llmod in
    set_attributes f
  | PUBLIC_IN ->
    let smack_ty = get_smack_ty llctx llmod in
    let vt = void_type llctx in
    let ft = function_type vt [| smack_ty |] in
    let f = declare_function (string_of_ct_verif PUBLIC_IN) ft llmod in
    set_attributes f
  | PUBLIC_OUT ->
    let smack_ty = get_smack_ty llctx llmod in
    let vt = void_type llctx in
    let ft = function_type vt [| smack_ty |] in
    let f = declare_function (string_of_ct_verif PUBLIC_OUT) ft llmod in
    set_attributes f
  | DECLASSIFIED_OUT ->
    let smack_ty = get_smack_ty llctx llmod in
    let vt = void_type llctx in
    let ft = function_type vt [| smack_ty |] in
    let f = declare_function (string_of_ct_verif DECLASSIFIED_OUT) ft llmod in
    set_attributes f
  | SMACK_VALUE ->
    let smack_ty = get_smack_ty llctx llmod in
    let ft = var_arg_function_type smack_ty [||] in
    let f = declare_function (string_of_ct_verif SMACK_VALUE) ft llmod in
    set_attributes f
  | SMACK_VALUES ->
    let smack_ty = get_smack_ty llctx llmod in
    let i8_ptr_ty = pointer_type (i8_type llctx) in
    let i32_ty = i32_type llctx in
    let ft = function_type smack_ty [| i8_ptr_ty; i32_ty |] in
    let f = declare_function (string_of_ct_verif SMACK_VALUES) ft llmod in
    set_attributes f
  | SMACK_RETURN_VALUE ->
    let smack_ty = get_smack_ty llctx llmod in
    let ft = function_type smack_ty [||] in
    let f = declare_function (string_of_ct_verif SMACK_RETURN_VALUE) ft llmod in
    set_attributes f

let codegen_dec vt llvalue llctx llmod llbuilder =
  let extract_label = function
    | RefVT(_,{data=Fixed(label)},_) ->
      let i32_ty = pointer_type (i32_type llctx) in
      Some(label,i32_ty)
    | ArrayVT(_,{data=Fixed(label)},_) ->
      Log.info "ARRAY: %s" (show_label' label);
      let ty = pointer_type (i32_type llctx) in
      Some(label,ty)
    | _ -> None 
  in
  let label = extract_label vt.data in
  match label with
    | None -> ()
    | Some(Unknown,_) -> ()
    | Some(Secret,_) -> ()
    | Some(Public,ty) ->
      let smack_ty = get_smack_ty llctx llmod in
      (* Bitcast the smack value *)
      let ret_ty = var_arg_function_type smack_ty [| ty; |] in
      let f = match lookup_function (string_of_ct_verif SMACK_VALUE) llmod with
        | None -> raise CTVerifError
        | Some f' -> f' in
      let cast = const_bitcast f (pointer_type ret_ty) in
      let v = build_call cast [|llvalue|] "" llbuilder in
      (* Call ct-verifs @public_in function *)
      let public_in = match lookup_function (string_of_ct_verif PUBLIC_IN) llmod with
        | None -> raise CTVerifError
        | Some public_in' -> public_in' in
      build_call public_in [| v |] "" llbuilder |> ignore

