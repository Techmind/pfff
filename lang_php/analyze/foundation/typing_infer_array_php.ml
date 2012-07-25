open Env_typing_php 
module THP = Typing_helpers_php
module APS = Ast_php_simple
module PI = Parse_info

module Array_typer = struct

exception Fun_def_error

  type evidence = 
    | SingleLine of PI.info option(*When a single line of evidence is enough,
    ex a no index access indicating a vector*)
    | DoubleLine of PI.info option * Env_typing_php.t *
    PI.info option * Env_typing_php.t (*When two conflicting
    lines are needed, ex inserting two different types*)

  type container_evidence = {
    supporting: evidence list;
    opposing: evidence list
  }

  type container = 
    | Vector of Env_typing_php.t
    | Tuple (*of Env_typing_php.t * Env_typing_php.t*)
    | Map of Env_typing_php.t * Env_typing_php.t
    | NoData (*Indicates insufficient data*)
    | NoGuess (*indicates conflicting data*)
    | NotArray (* May be present in a return type*)

  type declaration = 
    | DKeyValue
    | DValue
    | NoDec

  type inferred_container = {
    map: container_evidence;
    tuple: container_evidence; 
    vector: container_evidence;
    guess: container;
    confused: bool;
    mixed_val_ty: bool;
    key_t: Env_typing_php.t option;
    value_t: Env_typing_php.t option;
    declaration: declaration;
    parameter: bool;
    dec_loc: PI.info option;
    return_val: bool;
    fdef_loc: PI.info option
  }

  type evidence_type = 
    | Supporting
    | Opposing

  let make_container_evidence = {
    supporting = [];
    opposing = [];
  }

  let compose_ce s o = {
    supporting = s;
    opposing = o
  }

  let add_evidence ce et e = 
    let {supporting = s; opposing = o} = ce in
    match et with 
    | Supporting -> let s = e::s in
      compose_ce s o
    | Opposing -> let o = e::o in
      compose_ce s o

  let make_inferred_container = {
    map = make_container_evidence;
    tuple = make_container_evidence;
    vector = make_container_evidence;
    guess = NoData;
    confused = false;
    mixed_val_ty = false;
    key_t = None;
    value_t = None;
    declaration = NoDec;
    parameter = false;
    dec_loc = None;
    return_val = false;
    fdef_loc = None
  }

  (* TODO: refactor to remove this fcn *)
  let compose_ic m t v g c mt k va d p dl r fd = {
    map = m;
    tuple = t;
    vector = v;
    guess = g;
    confused = c;
    mixed_val_ty = mt;
    key_t = k;
    value_t = va;
    declaration = d;
    parameter = p;
    dec_loc = dl;
    return_val = r;
    fdef_loc = fd
  }

  type cont_evi = container * int list

  type val_evi = Env_typing_php.t * evidence

  type patch = int * string (* line number * new line text *)

  type t = {
    (* intermediate structure - contains list of value types associated with the
     * array, and a list of line numbers *)
    values: val_evi list AMap.t ref;
    (* Final inferred type confidences*)
    inferred: inferred_container AMap.t ref;
    (* Map to store patches for the file associated with the key *)
    patches: patch list SMap.t ref
  }

  let rec is_in_patch_list ln l = 
    match l with 
    | [] -> false
    | (ln_t, _)::xs when ln_t = ln -> true
    | x::xs -> is_in_patch_list ln xs

  let is_line_patched ln file at = 
    let file_patches = try SMap.find file !(at.patches) with Not_found -> [] in
    is_in_patch_list ln file_patches

  let rec get_patch_from_list ln l = 
    match l with 
    | [] -> ""
    | (ln_t, pline)::xs when ln_t = ln -> pline
    | x::xs -> get_patch_from_list ln xs

  let get_patched_line at file ln = 
    let file_patches = try SMap.find file !(at.patches) with Not_found -> [] in
    get_patch_from_list ln file_patches

  let add_patch_to_patch_list at file ln line = 
    let file_patches = try SMap.find file !(at.patches) with Not_found -> [] in
    let file_patches = (ln, line)::file_patches in
    at.patches := SMap.add file file_patches !(at.patches)

  let make_array_typer f = {
    values = ref AMap.empty;
    inferred = ref AMap.empty;
    patches = ref SMap.empty;
  }

  let fun_on_aenv env at f =
    THP.AEnv.iter env (
      fun x l -> f at x l;)
 
  let print_keys env =
    THP.AEnv.iter env (
      fun x l ->
      match x with
      | (e, f, c) -> ( let stmt = APS.Expr (e) in
        let v = Meta_ast_php_simple.vof_program [stmt] in
        let s = Ocaml.string_of_v v in
        Common.pr s;)
    )

  let line_of_array_info = function
    | (None, _) -> (-1)
    | (Some (pi), _) -> PI.line_of_info pi

  let pp_arr_id id = 
    match id with 
    | (e, f, c) -> 
        Printf.printf "In %s %s, " c f;
        let stmt = APS.Expr(e) in
        let v = Meta_ast_php_simple.vof_program [stmt] in
        let s = Ocaml.string_of_v v in
        Common.pr s

  let rec check_id_in_list id l = 
    match id with 
    | (e, f, c) -> 
      match l with 
      | [] -> false
      | (e1, f1, c1)::xs when f1 = f && c1 = c && (Ast_php_simple.expr_equal e e1)
        -> true
      | (e1, f1, c1)::xs when (Ast_php_simple.expr_equal e e1 )->
          Printf.printf "Expressions same\n"; false
      | (e1, f1, c1)::xs when f1 = f -> Printf.printf "Functions same\n";
        false
      | (e1, f1, c1)::xs when c1 = c -> Printf.printf "Classes same\n";
        false
      | x::xs -> Printf.printf "None correct\n"; check_id_in_list id xs

  let is_parameter env id =
    Printf.printf "is_parameter\n";
    let params = THP.AEnv.get_params env in
    Printf.printf "Number of params %d" (List.length params);
    check_id_in_list id params


  let string_equ t1 t2 = 
    match t1, t2 with 
    | Tsum[Tsstring _], Tsum[Tsstring _] 
    | Tsum[Tsstring _], Tsum[Tabstr "string"]
    | Tsum[Tabstr "string"], Tsum[Tsstring _] -> true
    | Tsum[Tabstr s1], Tsum[Tabstr s2] when s1 = s2 -> true
    | Tvar v1, Tvar v2 when v1 = v2 -> true
    | _, _ -> false

  let apply_subst env x = 
    match x with 
    | Tsum _ -> x
    | Tvar v -> THP.TEnv.get env v

  let analyze_noindex env at id pi v =
    let v = apply_subst env v in
    let ic = try AMap.find id !(at.inferred) with Not_found ->
      make_inferred_container in
    let {map = m; tuple = t; vector = ve; key_t = key; value_t = va;
      mixed_val_ty = mt; _} = ic in
    let p = is_parameter env id in
    let e = SingleLine(pi) in
    let m = add_evidence m Opposing e in
    let t = add_evidence t Opposing e in
    let k = Tsum[Tabstr "int"] in
    let ic = {ic with map = m; tuple = t; parameter = p} in
    match key, va with
    | Some(key_t), _ when key_t <> k && not (string_equ key_t k) ->
      let ic = {ic with confused = true; mixed_val_ty = true} in
      at.inferred := AMap.add id ic !(at.inferred)
    | _, _ when mt ->
      let ic = {ic with confused = true} in
      at.inferred := AMap.add id ic !(at.inferred)
    | _, Some(va) when (va = v || string_equ va v) -> 
      let ve = add_evidence ve Supporting e in
      let ic = {ic with vector = ve; guess = (Vector(v))} in
      at.inferred := AMap.add id ic !(at.inferred)
    | _, Some(va) -> 
      let ic = {ic with confused = true; mixed_val_ty = true} in
      at.inferred := AMap.add id ic !(at.inferred)
    | _, None -> 
      let va = Some(v) in
      let key = Some(k) in
      let ve = add_evidence ve Supporting (SingleLine(pi)) in
      let ic = {ic with guess = (Vector(v)); vector = ve; key_t = key; value_t = va} in
      at.inferred := AMap.add id ic !(at.inferred)
    

  let rec contains_type t l = 
    match l with 
    | [] -> None
    | (y, pi)::xs when (y <> t && not (string_equ y t))-> Some(y, pi)
    | x::xs -> contains_type t xs

  let prev_conflicting_val at id v pi =
    let e = SingleLine(pi) in
    let ve = try AMap.find id !(at.values) with Not_found -> [] in
    let ct = contains_type v ve in
    if (List.length ve = 0) || (List.length ve = 1 && ct = None) 
    then (let ve = (v, e)::ve in 
      at.values := AMap.add id ve !(at.values);
      None) 
    else (let ve = (v, e)::ve in 
      at.values := AMap.add id ve !(at.values);
      ct)

  let pi_of_evidence evi = 
    match evi with 
    | SingleLine(pi) -> pi
    | DoubleLine(pi, _, _, _) -> pi

  let analyze_value env at id pi v =
    let v = apply_subst env v in
    match prev_conflicting_val at id v pi with
    | None -> ()
    | Some(t, tpi) -> 
      let tpi = pi_of_evidence tpi in
      let evi = DoubleLine(pi, v, tpi, t) in
      let ic = try AMap.find id !(at.inferred) with Not_found ->
        make_inferred_container in 
      let {map = map; vector = vector; _ } = ic in
      let p = is_parameter env id in 
      let map = add_evidence map Opposing evi in 
      let vector = add_evidence vector Opposing evi in 
      let ic = {ic with parameter = p; map = map; vector = vector; mixed_val_ty
      = true} in
      at.inferred := AMap.add id ic !(at.inferred)

  let print_val_types env va_t v = 
    let penv = Pp2.empty print_string in
    THP.Print2.ty env penv ISet.empty 0 va_t;
    THP.Print2.ty env penv ISet.empty 0 v;
    match va_t, v with 
    | Tsum _, Tsum _  -> Printf.printf "Tsums\n"
    | Tvar v1, Tvar v2 -> Printf.printf "Tvars %d and %d\n" v1 v2
    | Tsum _, Tvar _  -> Printf.printf "v is a var\n"
    | Tvar _, Tsum _ -> Printf.printf "va_t is a var\n"

  let analyze_declaration_value env at id pi v = 
    let v = apply_subst env v in
    let ic = try AMap.find id !(at.inferred) with Not_found ->
      make_inferred_container in
    let {map = m; tuple = t; vector = ve; key_t = key; value_t = va; declaration 
    = d; _} = ic in
    let e = SingleLine(pi) in
    let p = is_parameter env id in
    let dl = pi in
    let ic = {ic with parameter = p; dec_loc = dl} in
    let k = Tsum[Tabstr "int"] in
      match d with 
      | DKeyValue ->
        let ic = {ic with guess = NoGuess; confused = true; declaration =
          DValue} in
        at.inferred := AMap.add id ic !(at.inferred)

      | DValue -> (match key, va with 
        | None, None -> 
          let key = Some (k) in
          let va = Some(v) in
          let ve = add_evidence ve Supporting e in
          let m = add_evidence m Opposing e in 
          let t = add_evidence t Supporting e in
          let ic = {ic with key_t = key; value_t = va; vector = ve; map = m;
            tuple = t; declaration = DValue} in
          at.inferred := AMap.add id ic !(at.inferred)

        | Some(key_t), Some(ty) when (ty = v || string_equ ty v) && (key_t = k
          || string_equ key_t k) -> 
          let ve = add_evidence ve Supporting e in
          let m = add_evidence m Opposing e in 
          let t = add_evidence t Supporting e in
          let ic = {ic with vector = ve; map = m; tuple = t; declaration =
            DValue} in
          at.inferred := AMap.add id ic !(at.inferred)
      
        | Some(key_t), Some (va_t) when key_t = k || string_equ key_t k ->
          let m = add_evidence m Opposing e in
          let ve = add_evidence ve Opposing e in
          let t = add_evidence t Supporting e in
          let ic = {ic with map = m; vector = ve; tuple = t; guess = Tuple;
            mixed_val_ty = true; declaration = DValue} in
          at.inferred := AMap.add id ic !(at.inferred)

        | _, _ -> 
          let ic = {ic with confused = true} in
          at.inferred := AMap.add id ic !(at.inferred)
      )

      | NoDec -> 
        let key = Some (Tsum[Tabstr "int"] ) in
        let va = Some(v) in
        let g = Vector v in
        let e = SingleLine(pi) in
        let m = add_evidence m Opposing e in
        let t = add_evidence t Supporting e in
        let ve = add_evidence ve Supporting e in
        let ic = {ic with key_t = key; value_t = va; guess = g; map = m; tuple =
          t; vector = ve; declaration = DValue} in
        at.inferred := AMap.add id ic !(at.inferred)

  let analyze_declaration_kvalue env at id pi k v  = 
    let k = apply_subst env k in
    let v = apply_subst env v in
    let ic = try AMap.find id !(at.inferred) with Not_found ->
      make_inferred_container in
    let {map = m; tuple = t; vector = ve; key_t = key; value_t = va; declaration
      = d; _}  = ic in
    let e = SingleLine(pi) in
    let dl = pi in
    let p = is_parameter env id in
    let ic = {ic with parameter = p; dec_loc = dl} in
    match d with 
    | DValue -> 
      let ic = {ic with guess = NoGuess; confused = true; declaration =
        DKeyValue} in
      at.inferred := AMap.add id ic !(at.inferred)
    
    | DKeyValue
    | NoDec -> ( 
      match key, va with 
      | Some(key_t), Some(va_t) when (key_t = k || string_equ key_t k) &&
      (va_t = v || string_equ va_t v)-> 
        let m = add_evidence m Supporting e in
        let ve = add_evidence ve Opposing e in
        let t = add_evidence t Opposing e in
        let g = Map (key_t, va_t) in
        let ic = {ic with map = m; vector = ve; tuple = t; guess = g;
          declaration = DKeyValue} in
        at.inferred := AMap.add id ic !(at.inferred)
        
      | None, None -> 
        let key = Some(k) in
        let va = Some(v) in
        let m = add_evidence m Supporting e in
        let ve = add_evidence ve Opposing e in
        let t = add_evidence t Opposing e in
        let g = Map (k, v) in
        let ic = {ic with key_t = key; value_t = va; map = m; vector = ve;
          tuple = t; guess = g; declaration = DKeyValue} in
        at.inferred := AMap.add id ic !(at.inferred)

      | _, _ -> 
        let ic = {ic with guess = NoGuess; confused = true; declaration =
          DKeyValue} in
        at.inferred := AMap.add id ic !(at.inferred)
      )

  let analyze_nonstring_access env at id pi k v = 
    let k = apply_subst env k in 
    let v = apply_subst env v in
    let ic = try AMap.find id !(at.inferred) with Not_found ->
      make_inferred_container in 
    let {map = m; tuple = t; vector = ve; key_t = key; value_t = va; _} = ic in
    let e = SingleLine(pi) in
    let p = is_parameter env id in
    let ic = {ic with parameter = p} in
    match key, va with 
    | Some(key_t), _ when (key_t <> k && not (string_equ key_t k))->
      let ic = {ic with guess = NoGuess; confused = true} in
      at.inferred := AMap.add id ic !(at.inferred)

    | Some(key_t), Some(va_t) when (key_t = k || string_equ key_t k) && k <>
      Tsum[Tabstr "int"] && (va_t = v || string_equ va_t v)-> 
      let m = add_evidence m Supporting e in 
      let ve = add_evidence ve Opposing e in
      let t = add_evidence t Opposing e in
      let g = Map (key_t, va_t) in
      let ic = {ic with map = m; vector = ve; tuple = t; guess = g} in
      at.inferred := AMap.add id ic !(at.inferred)
    
    | Some(key_t), Some(va_t) when (key_t = k || string_equ key_t k) && k =
      Tsum[Tabstr "int"] && (va_t = v || string_equ va_t v) -> 
      at.inferred := AMap.add id ic !(at.inferred)
    
    | Some(Tsum[Tabstr "int"]), Some(va_t) when (va_t <> v && not (string_equ
      va_t v)) ->
      let m = add_evidence m Opposing e in
      let ve = add_evidence ve Opposing e in 
      let t = add_evidence t Supporting e in
      let ic = {ic with map = m; vector = ve; tuple = t; guess = Tuple;
        mixed_val_ty = true} in
      at.inferred := AMap.add id ic !(at.inferred)
    
    | None, None -> (*also doesn't really tell me anything*)
      let key = Some(k) in 
      let va = Some(v) in
      let ic = {ic with key_t = key; value_t = va} in
      at.inferred := AMap.add id ic !(at.inferred)
    
    | _, _ ->
      at.inferred := AMap.add id ic !(at.inferred)

  let analyze_string_access env at id pi v = 
    let v = apply_subst env v in 
    let ic = try AMap.find id !(at.inferred) with Not_found ->
      make_inferred_container in
    let {map = m; tuple = t; vector = ve; key_t = key; value_t = va; _} = ic in
    let e = SingleLine(pi) in
    let p = is_parameter env id in
    let t = add_evidence t Opposing e in 
    let ve = add_evidence ve Opposing e in
    let ic = {ic with parameter = p; tuple = t; vector = ve} in
    let k = Tsum[Tabstr "string"] in 
    match key, va with 
    | None, None -> 
      let key = Some(k) in
      let va = Some(v) in 
      let m = add_evidence m Supporting e in
      let g = Map (k, v) in
      let ic = {ic with key_t = key; value_t = va; map = m; guess = g} in
      at.inferred := AMap.add id ic !(at.inferred)
    | Some(key_t),  Some(va_t) when (va_t = v || string_equ va_t v) && (key_t =
      k || string_equ key_t k) -> 
      let m = add_evidence m Supporting e in
      let g = Map (key_t, va_t) in
      let ic = {ic with map = m; guess = g} in
      at.inferred := AMap.add id ic !(at.inferred)
    | _, _ -> 
      let m = add_evidence m Opposing e in
      let ic = {ic with map = m; confused = true; mixed_val_ty = true} in
      at.inferred := AMap.add id ic !(at.inferred)

  let declared_array at id pi = 
    let ic = try AMap.find id !(at.inferred) with Not_found ->
      make_inferred_container in
    let ic = {ic with dec_loc = pi } in
    at.inferred := AMap.add id ic !(at.inferred)

  let initialize_inferred_container at id = 
    if not (AMap.mem id !(at.inferred)) then 
      let ic = make_inferred_container in 
      at.inferred := AMap.add id ic !(at.inferred)

  let set_return at id pi = 
    let ic = try AMap.find id !(at.inferred) with Not_found ->
      make_inferred_container in 
    let ic = {ic with return_val = true; fdef_loc = pi} in 
    at.inferred := AMap.add id ic !(at.inferred)

  let analyze_access_info env at id ail = 
    List.iter (fun ai -> 
      match ai with
      | (pi, NoIndex (v)) -> analyze_noindex env at id pi v
      | (pi, VarOrInt (k, v)) -> analyze_nonstring_access env at id pi k v
      | (_, Const _) -> initialize_inferred_container at id
      | (pi, ConstantString v) -> analyze_string_access env at id pi v
      | (pi, DeclarationValue v) -> analyze_declaration_value env at id pi v
      | (pi, DeclarationKValue (k, v)) -> analyze_declaration_kvalue env at id pi k v
      | (pi, Declaration _ ) -> declared_array at id pi
      | (pi, Value v) -> analyze_value env at id pi v
      | (_, UnhandledAccess) -> initialize_inferred_container at id
      | (_, Parameter) -> ()
      | (pi, ReturnValue) -> set_return at id pi
    ) ail

  let analyze_accesses_values env at = 
    THP.AEnv.iter env (fun id ail -> 
      analyze_access_info env at id ail;
    )
  
  let infer_arrays env at =
    Printf.printf "Inferring arrays ...\n";
    analyze_accesses_values env at
  
  (* x is the id, l is the list of arr_info (parse_info option * arr_access )*)
  let string_of_container = function
    | Vector _ -> "vector"
    | Tuple -> "tuple"
    | Map _ -> "map"
    | NoData -> "no data"
    | NoGuess -> "conflicting data exists"
    | NotArray -> "not an array"

  let rec pp_evidence e = 
    List.iter (fun x ->
      Printf.printf "    %d\n" x; 
      )
    e

  let pp_cont_evi x =
    match x with
    | (c, e) -> begin Printf.printf "  %s\n" (string_of_container c);
    pp_evidence e; end

  let pp_evidence e = 
    match e with 
    | SingleLine (Some pi) -> Printf.printf "    Evidence in file %s on line %d at %d\n"
    (PI.file_of_info pi) (PI.line_of_info pi)
    (PI.col_of_info pi)
    | DoubleLine (Some pi1, e1, Some pi2, e2) -> 
        Printf.printf "     Evidence in file %s on line %d at %d and evidence in
  file %s on line %d at %d\n"
      (PI.file_of_info pi1) (PI.line_of_info pi1)
      (PI.col_of_info pi1)
      (PI.file_of_info pi2) (PI.line_of_info pi2)
      (PI.col_of_info pi2)
    | _ -> Printf.printf "    Evidence unavailable"

  let rec pp_evidence_l cel = 
    match cel with 
    | [] -> ()
    | x::xs -> pp_evidence x; pp_evidence_l xs

  let pp_confused_reasoning ic = 
    let {map = m; tuple = t; vector = v; guess = guess; confused = c;
    mixed_val_ty = _; key_t = _; value_t = _; declaration = _; parameter = _;
    dec_loc = _; _} = ic in
    let {supporting = _; opposing = o} = m in
    Printf.printf "    Not a map due to:\n";
    pp_evidence_l o;
    let {supporting = _; opposing = o} = t in
    Printf.printf "    Not a tuple due to:\n";
    pp_evidence_l o;
    let {supporting = _; opposing = o} = v in
    Printf.printf "    Not a vector due to:\n";
    pp_evidence_l o
    

  let pp_reasoning ic = 
    let {map = m; tuple = t; vector = v; guess = guess; confused = c;
    mixed_val_ty = _; key_t = _; value_t = _; declaration = _; parameter = _;
    dec_loc = _; _} = ic in
      match guess with
      | Map _ ->
        let {supporting = s; opposing = _} = m in
        pp_evidence_l s
      | Tuple -> 
        let {supporting = s; opposing = _} = t in 
        pp_evidence_l s
      | Vector _ -> 
        let {supporting = s; opposing = _} = v in
        pp_evidence_l s
      | _ -> ()

  let pp_array_guesses at =
    AMap.iter (fun id ic ->
      pp_arr_id id;
      let {map = _; tuple = _; vector = _; guess = guess; confused = c;
      mixed_val_ty = _; key_t = _; value_t = _; declaration = _; parameter = _;
      dec_loc = _; _} = ic in
      match c with 
      | true -> 
          Printf.printf "  conflicting data exists\n";
          pp_confused_reasoning ic
      | false -> 
          Printf.printf "  %s\n" (string_of_container guess);
          pp_reasoning ic
    ) !(at.inferred)

  let pp_param_arrays at =
    Printf.printf "Arrays that are parameters\n";
    AMap.iter (fun id ic -> 
      let {map = _; tuple = _; vector = _; guess = _; confused = _;
      mixed_val_ty = _; key_t = _; value_t = _; declaration = _; parameter = p;
      dec_loc = _; _} = ic in
      if p then (pp_arr_id id)
      ) !(at.inferred)

  let file_lines f = 
    let lines = ref [] in
    let in_ch = open_in f in
    try while true; do
      lines := input_line in_ch ::!lines
    done; []
    with End_of_file -> 
      close_in in_ch;
      List.rev !lines

  let get_line_to_patch at pi lines = 
    let ln = PI.line_of_info pi in
    let file = PI.file_of_info pi in
    if is_line_patched ln file at then 
      get_patched_line at file ln
    else List.nth lines (ln - 1)

  let write_patch f lines = 
    let f = f^"-p" in
    let out_ch = open_out f in
    List.iter (fun l -> output_string out_ch (l^"\n")) lines;
    close_out out_ch;
    Printf.printf "Patch applied \n"

  let rec insert_patched_line_to_list ln newl lines c =
    match lines with 
    | [] -> []
    | x::xs when ln = c -> newl::xs
    | x::xs -> x:: (insert_patched_line_to_list ln newl xs (c+1))
    

  let prompt_patched_line at file old_line line line_n = 
    Printf.printf "%s\n" old_line;
    Printf.printf "%s\n" line;
    Printf.printf "Would you like to apply this patch? (y/n)\n";
    let patch = read_line () in 
    if patch = "y" then
      (
        Printf.printf "Patch selected\n";
        add_patch_to_patch_list at file line_n line
      )
    else Printf.printf "Patch not selected\n"

  let suggest_patch_declaration at g pi lines = 
    let ln = (PI.line_of_info pi) - 1 in
    let file = PI.file_of_info pi in
    let line_to_patch = get_line_to_patch at pi lines in
    let arr_regex = Str.regexp "array" in
    match g with 
    | Vector _ -> 
        let patched_line = Str.replace_first arr_regex "Vector" line_to_patch in
        prompt_patched_line at file line_to_patch patched_line ln
    | Tuple -> 
        let patched_line = Str.replace_first arr_regex "Tuple" line_to_patch in
        prompt_patched_line at file line_to_patch patched_line ln
    | Map (Tsum[Tsstring _], _) 
    | Map (Tsum[Tabstr "string"], _) -> 
        let patched_line = Str.replace_first arr_regex "StrMap" line_to_patch in 
        prompt_patched_line at file line_to_patch patched_line ln
    | Map (Tsum[Tabstr "int"], _) -> 
        let patched_line = Str.replace_first arr_regex "IntMap" line_to_patch in
        prompt_patched_line at file line_to_patch patched_line ln
    | _ -> 
        Printf.printf "Sorry, no patch can be applied to \n";
        Printf.printf "%s\n" line_to_patch

    let patch_declaration at ic =
      let {dec_loc = dl; confused = c; guess = g; parameter = p; _} = ic in
      match dl with
      | None -> ()
      | Some(pi) ->
        let lines = file_lines (PI.file_of_info pi) in
        if (not c && not (g = NoData)) then(
          if p then(
            Printf.printf "Is a parameter, patch the parameter\n"
          )
          else (
          (* If is a parameter, TODO function that converts, else *)
          Printf.printf "Declared at in %s line %d position %d\n"
            (PI.file_of_info pi) (PI.line_of_info pi) (PI.col_of_info pi);
          Printf.printf "This array may be a %s due to the following evidence: \n"
            (string_of_container g);
          pp_reasoning ic;
          suggest_patch_declaration at g pi lines
          )
        )
        else if c then 
          ( Printf.printf "Confused about the array declared on %d at %d due to the following: \n"
          (PI.line_of_info pi) (PI.col_of_info pi);
          pp_confused_reasoning ic )
        else (* No data *)
          Printf.printf "No data about the array declared on %d at %d \n"
          (PI.line_of_info pi) (PI.col_of_info pi)

    (*let patch_return_val_line *)

    let rec unsplit_list l = 
      match l with 
      | [] -> ""
      | x::xs -> ")"^x^(unsplit_list xs)

    let insert_return_value line_to_patch return_type_str = 
      let spl_line = Str.split (Str.regexp ")") line_to_patch in
      match spl_line with
      | [] -> raise Fun_def_error
      | x::xs -> x^return_type_str^(unsplit_list xs)

    let suggest_patch_return_val env at g pi lines = 
      let ln = (PI.line_of_info pi) - 1 in 
      let file = PI.file_of_info pi in 
      let line_to_patch = get_line_to_patch at pi lines in 
      match g with 
      | Vector t -> 
          let t_string = THP.Type_string.ty env ISet.empty 0 t in 
          let t_string = "): Vector <"^t_string^">" in
          let patched_line = insert_return_value line_to_patch t_string in
          prompt_patched_line at file line_to_patch patched_line ln
      | Tuple _ -> 
          let t_string = "): Tuple " in
          let patched_line = insert_return_value line_to_patch t_string in
          prompt_patched_line at file line_to_patch patched_line ln
      | Map (Tsum[Tsstring _], _) 
      | Map (Tsum[Tabstr "string"], _) -> 
          let t_string = "type" in 
          let t_string = "): StrMap <"^t_string^">" in
          let patched_line = insert_return_value line_to_patch t_string in
          prompt_patched_line at file line_to_patch patched_line ln
      | Map (Tsum[Tabstr "int"], t) -> 
          let t_string = THP.Type_string.ty env ISet.empty 0 t in 
          let t_string = "): IntMap <"^t_string^">" in
          let patched_line = insert_return_value line_to_patch t_string in
          prompt_patched_line at file line_to_patch patched_line ln
      | _ -> Printf.printf "Sorry, no patch can be applied\n"

    let patch_return_value env at ic =
      let {fdef_loc = fd; confused = c; guess = g; _} = ic in
      match fd with 
      | None -> ()
      | Some(pi) ->
        let lines = file_lines (PI.file_of_info pi) in
        if (not c && not (g = NoData)) then (
        Printf.printf "An array is returned from the function defined in %s at
        line %d\n" (PI.file_of_info pi) (PI.line_of_info pi);
        Printf.printf "%s\n" (List.nth lines ((PI.line_of_info pi) -1));
        Printf.printf "The returned array may be a %s due to the following
        evidence: \n" (string_of_container g);
        pp_reasoning ic;
        suggest_patch_return_val env at g pi lines
        )
    let rec write_lines pl lines out_ch ln = 
      match pl, lines with
      | _, [] -> ()
      | (ln1, line1)::xs1, line2::xs2 when ln1 = ln ->
          output_string out_ch (line1^"\n");
          write_lines xs1 xs2 out_ch (ln+1)
      | _, line::xs -> 
          output_string out_ch (line^"\n");
          write_lines pl xs out_ch (ln+1)

    let write_file_patches file pl lines = 
      let file = file^"-p" in
      let out_ch = open_out file in
      write_lines pl lines out_ch 0;
      close_out out_ch

    let compare_patches p1 p2 = 
      match p1, p2 with 
      | (l1, _), (l2, _) when l1 < l2 -> (-1)
      | (l1, _), (l2, _) when l1 > l2 -> 1
      | (l1, _), (l2, _) -> 0

    let apply_file_patches file pl = 
      let pl = List.sort compare_patches pl in
      Printf.printf "%s: %d changes" file (List.length pl);
      let lines = file_lines file in
      write_file_patches file pl lines
    
    let apply_all_patches at = 
      SMap.iter apply_file_patches !(at.patches)

    let patch_suggestion env at = 
    Printf.printf "Preparing to patch files \n";
    AMap.iter (fun id ic ->
      let {dec_loc = dl; parameter = _; confused = c; guess = g; return_val = r;
      fdef_loc = fd; _} = ic in
      if not (g = NotArray) && r then (
        patch_declaration at ic;
        patch_return_value env at ic
      )
      
      else if not (g = NotArray) then patch_declaration at ic
    ) !(at.inferred); 
    apply_all_patches at

end
