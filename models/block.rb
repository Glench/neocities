class Block < Sequel::Model
  many_to_one :site
  many_to_one :actioning_site, class: :Block
end