// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.payload.payload

// Payload metadata for a point: a schemaless list of typed fields, its WAL
// codec (durable metadata), and the id -> Payload store. Extracted from the
// consolidated engine (first layer of the post-AUDIT module tree).

use xiom.num.float;
use xiom.string.slice;

// Tagged scalar carried by a payload field.
pub enum FieldValue {
  IntVal(v: Int),
  FloatVal(v: Float32),
  TextVal(v: Str),
  BoolVal(v: Bool),
}

pub type PayloadField = {
  key: Str;
  value: FieldValue;
}

pub type Payload = {
  fields: Vec[PayloadField];
}

pub fn payload_new() -> Payload {
  var fields = Vec[PayloadField].new();
  return Payload{ fields: fields };
}

// Set or OVERWRITE a field (linear scan; a sorted key index is a later
// Phase 3 deliverable).
pub fn payload_set(p: &mut Payload, key: Str, value: FieldValue) {
  var i: Int = 0;
  while i < p.fields.len() {
    if p.fields[i].key == key {
      p.fields[i].value = value;
      return;
    }
    i = i + 1;
  }
  p.fields.push(PayloadField{ key: key, value: value });
}

pub fn payload_has(p: &Payload, key: Str) -> Bool {
  var i: Int = 0;
  while i < p.fields.len() {
    if p.fields[i].key == key { return true; }
    i = i + 1;
  }
  return false;
}

pub fn payload_get(p: &Payload, key: Str) -> Option[FieldValue] {
  var i: Int = 0;
  while i < p.fields.len() {
    if p.fields[i].key == key { return Some(p.fields[i].value); }
    i = i + 1;
  }
  return None;
}

pub fn payload_len(p: &Payload) -> Int {
  return p.fields.len();
}

pub fn field_value_kind(v: &FieldValue) -> Str {
  match v {
    IntVal(_) => "int",
    FloatVal(_) => "float",
    TextVal(_) => "text",
    BoolVal(_) => "bool",
  }
}

// Exact equality within one type; cross-type comparisons are false.
pub fn field_value_eq(a: &FieldValue, b: &FieldValue) -> Bool {
  match a {
    IntVal(av) => {
      match b { IntVal(bv) => { return av == bv; } _ => { return false; } }
    }
    FloatVal(av) => {
      match b { FloatVal(bv) => { return av == bv; } _ => { return false; } }
    }
    TextVal(av) => {
      match b { TextVal(bv) => { return av == bv; } _ => { return false; } }
    }
    BoolVal(av) => {
      match b { BoolVal(bv) => { return av == bv; } _ => { return false; } }
    }
  }
}

// Numeric view for Range: Int promotes to Float32, non-numeric -> None.
pub fn field_value_as_float(v: &FieldValue) -> Option[Float32] {
  match v {
    FloatVal(f) => { return Some(f); }
    IntVal(i) => { return Some(i as Float32); }
    _ => { return None; }
  }
}

// ---- Payload WAL codec (durable metadata) ----
// Word layout: [version=1, field_count,
//   (key_len, key_bytes...), kind, value_words...
// kind 1=int (v), 2=float (f64 bit pattern of the f32), 3=text (len, bytes),
// 4=bool (0|1)]. Decode is strict; malformed -> None (torn-record tolerance).
fn push_str_words(out: &mut Vec[Int], s: Str) {
  var bytes = slice.str_bytes(s);
  out.push(bytes.len());
  var i: Int = 0;
  while i < bytes.len() {
    out.push(bytes[i] as Int);
    i = i + 1;
  }
}

pub fn payload_encode(p: &Payload) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(1);
  out.push(p.fields.len());
  var i: Int = 0;
  while i < p.fields.len() {
    push_str_words(&mut out, p.fields[i].key);
    var fv = p.fields[i].value;
    match fv {
      IntVal(v) => { out.push(1); out.push(v); }
      FloatVal(f) => { out.push(2); out.push(float.float_bits(f as Float64)); }
      TextVal(t) => { out.push(3); push_str_words(&mut out, t); }
      BoolVal(b) => {
        out.push(4);
        if b { out.push(1); } else { out.push(0); }
      }
    }
    i = i + 1;
  }
  return out;
}

pub fn payload_decode(words: &Vec[Int]) -> Option[Payload] {
  if words.len() < 2 { return None; }
  if words[0] != 1 { return None; }
  var count = words[1];
  if count < 0 { return None; }
  var out = payload_new();
  var pos: Int = 2;
  var i: Int = 0;
  while i < count {
    if pos >= words.len() { return None; }
    var klen = words[pos];
    pos = pos + 1;
    if klen < 0 || pos + klen > words.len() { return None; }
    var kb = Vec[UInt8].new();
    var j: Int = 0;
    while j < klen {
      kb.push(words[pos + j] as UInt8);
      j = j + 1;
    }
    pos = pos + klen;
    var key = Str::from_utf8(kb);
    if pos >= words.len() { return None; }
    var kind = words[pos];
    pos = pos + 1;
    if kind == 1 {
      if pos >= words.len() { return None; }
      var iv = words[pos];
      pos = pos + 1;
      payload_set(&mut out, key, FieldValue.IntVal(iv));
    } elif kind == 2 {
      if pos >= words.len() { return None; }
      var bits = words[pos];
      pos = pos + 1;
      payload_set(&mut out, key, FieldValue.FloatVal(float.bits_to_float(bits) as Float32));
    } elif kind == 3 {
      if pos >= words.len() { return None; }
      var tlen = words[pos];
      pos = pos + 1;
      if tlen < 0 || pos + tlen > words.len() { return None; }
      var tb = Vec[UInt8].new();
      var k: Int = 0;
      while k < tlen {
        tb.push(words[pos + k] as UInt8);
        k = k + 1;
      }
      pos = pos + tlen;
      payload_set(&mut out, key, FieldValue.TextVal(Str::from_utf8(tb)));
    } elif kind == 4 {
      if pos >= words.len() { return None; }
      var bv = words[pos];
      pos = pos + 1;
      payload_set(&mut out, key, FieldValue.BoolVal(bv != 0));
    } else {
      return None;
    }
    i = i + 1;
  }
  return Some(out);
}

// ---- Payload store: point id -> Payload (linear scan, swap-remove) ----
pub type PayloadEntry = {
  id: Int;
  payload: Payload;
}

pub type PayloadStore = {
  entries: Vec[PayloadEntry];
}

pub fn payload_store_new() -> PayloadStore {
  var entries = Vec[PayloadEntry].new();
  return PayloadStore{ entries: entries };
}

// Insert or replace the payload for `id`.
pub fn payload_store_put(s: &mut PayloadStore, id: Int, payload: Payload) {
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id {
      s.entries[i].payload = payload;
      return;
    }
    i = i + 1;
  }
  s.entries.push(PayloadEntry{ id: id, payload: payload });
}

pub fn payload_store_get(s: &PayloadStore, id: Int) -> Option[Payload] {
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id { return Some(s.entries[i].payload); }
    i = i + 1;
  }
  return None;
}

pub fn payload_store_remove(s: &mut PayloadStore, id: Int) -> Bool {
  var pos: Int = -1;
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id { pos = i; }
    i = i + 1;
  }
  if pos == -1 { return false; }
  var last: Int = s.entries.len() - 1;
  s.entries[pos] = s.entries[last];
  s.entries.pop();
  return true;
}

pub fn payload_store_len(s: &PayloadStore) -> Int {
  return s.entries.len();
}
