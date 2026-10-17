//! JSON laid out byte for byte as iOS's `JSONEncoder` writes it with `.prettyPrinted`, `.sortedKeys` and
//! `.withoutEscapingSlashes`, so a backup reads the same whichever phone wrote it: two-space indents, `"key" : value`,
//! empty containers split over two lines, numbers in their shortest form with whole numbers bare, and only quotes,
//! backslashes and control characters escaped.

use serde_json::Value;

pub fn encode(value: &Value) -> String {
    let mut out = String::new();
    write(value, &mut out, "");
    out
}

fn write(value: &Value, out: &mut String, indent: &str) {
    let inner = format!("{indent}  ");
    match value {
        Value::Object(map) => {
            out.push_str("{\n");
            // `Map` is ordered by key unless serde_json's `preserve_order` is on, which nothing here enables; sorting
            // keeps the layout right if it ever is.
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort();
            for (index, key) in keys.iter().enumerate() {
                out.push_str(&inner);
                string(key, out);
                out.push_str(" : ");
                write(&map[key.as_str()], out, &inner);
                if index + 1 < keys.len() {
                    out.push(',');
                }
                out.push('\n');
            }
            if keys.is_empty() {
                out.push('\n');
            }
            out.push_str(indent);
            out.push('}');
        }
        Value::Array(items) => {
            out.push_str("[\n");
            for (index, item) in items.iter().enumerate() {
                out.push_str(&inner);
                write(item, out, &inner);
                if index + 1 < items.len() {
                    out.push(',');
                }
                out.push('\n');
            }
            if items.is_empty() {
                out.push('\n');
            }
            out.push_str(indent);
            out.push(']');
        }
        Value::Null => out.push_str("null"),
        Value::Bool(flag) => out.push_str(if *flag { "true" } else { "false" }),
        Value::Number(number) => match number.as_f64() {
            Some(float) if number.is_f64() => out.push_str(&number_text(float)),
            _ => out.push_str(&number.to_string()),
        },
        Value::String(text) => string(text, out),
    }
}

fn string(value: &str, out: &mut String) {
    out.push('"');
    for c in value.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            c if c < ' ' => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
}

/// Swift's `description` of a `Double`: the shortest digits that read back as the same value, plain from 1e-4 up to 1e16
/// and in exponent form outside it, with a whole number written without a fraction.
pub fn number_text(value: f64) -> String {
    assert!(value.is_finite(), "JSON has no form for {value}");
    if value == 0.0 {
        return if value.is_sign_negative() { "-0".into() } else { "0".into() };
    }
    // `{:e}` gives the shortest digits that round-trip, as "d.ddde<exp>".
    let scientific = format!("{:e}", value.abs());
    let (mantissa, exponent) = scientific.split_once('e').expect("exponent form");
    let exponent: i32 = exponent.parse().expect("exponent");
    let digits: String = mantissa.chars().filter(|c| *c != '.').collect();
    let sign = if value < 0.0 { "-" } else { "" };
    if (-4..=15).contains(&exponent) {
        let plain = if exponent >= 0 {
            let point = exponent as usize + 1;
            if digits.len() <= point {
                format!("{digits}{}", "0".repeat(point - digits.len()))
            } else {
                format!("{}.{}", &digits[..point], &digits[point..])
            }
        } else {
            format!("0.{}{digits}", "0".repeat((-exponent - 1) as usize))
        };
        return format!("{sign}{plain}");
    }
    let mantissa = if digits.len() > 1 { format!("{}.{}", &digits[..1], &digits[1..]) } else { digits };
    format!("{sign}{mantissa}e{}{:02}", if exponent < 0 { "-" } else { "+" }, exponent.abs())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn numbers_are_written_as_swift_writes_them() {
        let cases = [
            (30.0, "30"),
            (4.65, "4.65"),
            (0.1 + 0.2, "0.30000000000000004"),
            (1e15, "1000000000000000"),
            (1e16, "1e+16"),
            (1.5e16, "1.5e+16"),
            (1e-5, "1e-05"),
            (0.0001, "0.0001"),
            (5e-324, "5e-324"),
            (-0.0, "-0"),
            (2.5e-7, "2.5e-07"),
            (-3.25, "-3.25"),
            (9007199254740993.0, "9007199254740992"),
            (123456789012345680.0, "1.2345678901234568e+17"),
            (1234567.891, "1234567.891"),
            (0.3333333333333333, "0.3333333333333333"),
            (1e21, "1e+21"),
            (1e-7, "1e-07"),
        ];
        for (value, written) in cases {
            assert_eq!(number_text(value), written, "{value:?}");
        }
    }

    #[test]
    fn layout_is_swifts() {
        let value = json!({"b": [], "a": {"z": 1, "y": "q\"\\/\u{1}"}, "c": [1.5, true, null]});
        let expected = "{\n  \"a\" : {\n    \"y\" : \"q\\\"\\\\/\\u0001\",\n    \"z\" : 1\n  },\n  \"b\" : [\n\n  ],\n  \"c\" : [\n    1.5,\n    true,\n    null\n  ]\n}";
        assert_eq!(encode(&value), expected);
        assert_eq!(encode(&json!({})), "{\n\n}");
    }
}
