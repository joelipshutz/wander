begin;

create extension if not exists pgtap;

select plan(11);

select is(
  app.restaurant_cuisine_guess('italian_restaurant', 'Restaurant', 'restaurants_food', 'Ugo', null),
  'Italian',
  'specific provider cuisine wins'
);

select is(
  app.restaurant_cuisine_guess('oyster_bar_restaurant', 'Restaurant', 'restaurants_food', 'The Oyster Room', null),
  'Oyster bar',
  'multi-word cuisine provider types select the most specific match'
);

select is(
  app.restaurant_cuisine_guess('japanese_restaurant', 'Restaurant', 'restaurants_food', 'American Sushi House', null),
  'Japanese',
  'provider evidence outranks name evidence'
);

select is(
  app.restaurant_cuisine_guess('restaurant', 'Restaurant', 'restaurants_food', 'Sushi Fumi', null),
  'Sushi',
  'place names provide a cuisine when provider data is generic'
);

select is(
  app.restaurant_cuisine_guess('restaurant', 'Restaurant', 'restaurants_food', 'Mario Pizzeria', null),
  'Pizza',
  'curated name aliases resolve common restaurant terms'
);

select is(
  app.restaurant_cuisine_guess('restaurant', 'Restaurant', 'restaurants_food', 'Ugo', 'https://www.cafeugo.com/'),
  'Italian',
  'website evidence is used after generic provider and name evidence'
);

select is(
  app.restaurant_cuisine_guess('restaurant', 'Restaurant', 'restaurants_food', 'The Corner', null),
  null,
  'generic restaurant data does not fabricate a cuisine'
);

select is(
  app.restaurant_cuisine_guess('restaurant', 'Restaurant', 'restaurants_food', 'Indianapolis Grill', null),
  null,
  'whole-term matching avoids cuisine substring false positives'
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'app.restaurant_cuisine_guess(text,text,text,text,text)'::regprocedure
  ),
  false,
  'cuisine inference is security invoker'
);

select ok(
  (
    select pg_get_functiondef(
      'app.restaurant_cuisine_guess(text,text,text,text,text)'::regprocedure
    ) like '%SET search_path TO ''''%'
  ),
  'cuisine inference pins an empty search path'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'app.restaurant_cuisine_guess(text,text,text,text,text)',
    'execute'
  ),
  'authenticated clients cannot execute the internal inference helper'
);

select * from finish();

rollback;
