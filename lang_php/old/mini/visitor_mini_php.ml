(* Yoann Padioleau
 *
 * Copyright (C) 2010 Facebook
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 * 
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
 *)

(* generated by ocamltarzan with: camlp4o -o /tmp/yyy.ml -I pa/ pa_type_conv.cmo pa_visitor.cmo  pr_o.cmo /tmp/xxx.ml  *)

open Ast_mini_php


(* hooks *)
type visitor_in = {
  kexpr: (expr  -> unit) * visitor_out -> expr  -> unit;
  kstmt: (stmt  -> unit) * visitor_out -> stmt  -> unit;
  ktop: (toplevel -> unit) * visitor_out -> toplevel  -> unit;
}

and visitor_out = {
  vexpr: expr  -> unit;
  vstmt: stmt -> unit;
  vtop: toplevel -> unit;
}

let default_visitor = 
  { kexpr   = (fun (k,_) x -> k x);
    kstmt   = (fun (k,_) x -> k x);
    ktop    = (fun (k,_) x -> k x);
  }

let v_unit x = ()
let v_string (s:string) = ()
let v_bool (s:bool) = ()
let v_ref aref x = () (* dont go into ref *)
let v_option v_of_a v = 
  match v with
  | None -> ()
  | Some x -> v_of_a x
let v_list of_a xs = 
  List.iter of_a xs

let (mk_visitor: visitor_in -> visitor_out) = fun vin ->

let rec v_expr x = 
  let k x =  match x with (v1, v2) ->

let v_expr_info { t = v_t } = let arg = (*v_phptype v_t*) () in ()
and v_exprbis =
  function
  | Bool v1 -> let v1 = v_bool v1 in ()
  | Number v1 -> let v1 = v_string v1 in ()
  | String v1 -> let v1 = v_string v1 in ()
  | Null -> ()
  | Var v1 -> let v1 = v_string v1 in ()
  | ArrayAccess ((v1, v2)) -> let v1 = v_expr v1 and v2 = v_expr v2 in ()
  | Assign ((v1, v2)) -> let v1 = v_expr v1 and v2 = v_expr v2 in ()
  | Binary ((v1, v2, v3)) ->
      let v1 = v_expr v1
      and v2 = (* Ast_php.v_binaryOp v2 *) () 
      and v3 = v_expr v3
      in ()
  | Funcall ((v1, v2)) ->
      let v1 = v_string v1 and v2 = v_list v_expr v2 in ()
in
let v1 = v_exprbis v1 and v2 = v_expr_info v2 in ()
  in
  vin.kexpr (k, all_functions) x
and v_stmt x =
  let k x = match x with
    | ExprStmt v1 -> let v1 = v_expr v1 in ()
    | Echo v1 -> let v1 = v_expr v1 in ()
    | If ((v1, v2, v3)) ->
        let v1 = v_expr v1 and v2 = v_stmt v2 and v3 = v_option v_stmt v3 in ()
    | While ((v1, v2)) -> let v1 = v_expr v1 and v2 = v_stmt v2 in ()
    | Block v1 -> let v1 = v_list v_stmt v1 in ()
    | Return v1 -> let v1 = v_option v_expr v1 in ()
  in
  vin.kstmt (k, all_functions) x

and v_toplevel x =
  let k x = match x with
    | FuncDef ((v1, v2, v3)) ->
        let v1 = v_string v1
        and v2 =
          v_list
            (fun (v1, v2) ->
              let v1 = v_string v1 and v2 = v_option v_expr v2 in ())
            v2
        and v3 = v_list v_stmt v3
        in ()
    | StmtList v1 -> let v1 = v_list v_stmt v1 in ()
  in
  vin.ktop (k, all_functions) x

and v_program v = v_list v_toplevel v
  


and all_functions =   
  {
    vexpr = v_expr;
    vstmt = v_stmt;
    vtop = v_toplevel;
  }
in
all_functions
