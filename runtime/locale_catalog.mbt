///|
/// Strict text catalogs keyed by stable presentation/UI identifiers.
/// Every locale has exactly the default catalog's key set; text never falls back.
pub(all) struct LocaleCatalogs {
  default_locale : String
  catalogs : Map[String, Map[String, String]]
} derive(Debug)

///|
/// Validate locale metadata and complete structural alignment before install.
pub fn LocaleCatalogs::new(
  default_locale~ : String,
  catalogs~ : Map[String, Map[String, String]],
) -> LocaleCatalogs raise {
  guard catalogs.get(default_locale) is Some(default_catalog) else {
    fail("default locale catalog is missing: \{default_locale}")
  }
  if !is_formal_locale(default_locale) {
    fail("invalid default locale: \{default_locale}")
  }
  let mut has_required_key = false
  for key, _ in default_catalog {
    has_required_key = true
    if key == "" {
      fail("locale catalog contains empty stable key")
    }
  }
  if !has_required_key {
    fail("default locale catalog is empty: \{default_locale}")
  }
  for locale, catalog in catalogs {
    if !is_formal_locale(locale) {
      fail("invalid supported locale: \{locale}")
    }
    for key, _ in default_catalog {
      if !catalog.contains(key) {
        fail("locale \{locale} is missing required key: \{key}")
      }
    }
    for key, _ in catalog {
      if !default_catalog.contains(key) {
        fail("locale \{locale} has unexpected key: \{key}")
      }
    }
  }
  { default_locale, catalogs }
}

///|
/// Resolve a stable text key through the selected locale. Unsupported locale
/// preferences use the project default; missing text is always an error.
pub fn LocaleCatalogs::resolve(
  self : LocaleCatalogs,
  requested_locale : String,
  stable_key : String,
) -> String raise {
  let supported : Array[String] = []
  for locale, _ in self.catalogs {
    supported.push(locale)
  }
  let locale = resolve_locale(requested_locale, supported, self.default_locale)
  guard self.catalogs.get(locale) is Some(catalog) else {
    fail("resolved locale catalog is missing: \{locale}")
  }
  match catalog.get(stable_key) {
    Some(text) => text
    None => fail("locale \{locale} is missing required key: \{stable_key}")
  }
}
