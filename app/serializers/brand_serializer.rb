class BrandSerializer < ApplicationSerializer
  attributes :id, :name, :slug, :is_active

  attributes :categories do |brand|
    brand.categories.map do |category|
      {
        id: category.id,
        name: category.name,
        slug: category.slug
      }
    end
  end
end
