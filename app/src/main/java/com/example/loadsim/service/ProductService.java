package com.example.loadsim.service;

import com.example.loadsim.model.Product;
import com.example.loadsim.repository.ProductRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
public class ProductService {

    private final ProductRepository repo;

    @Cacheable(value = "products", key = "'page:' + #page + ':' + #size")
    @Transactional(readOnly = true)
    public List<Product> findAll(int page, int size) {
        Page<Product> result = repo.findAll(PageRequest.of(page, size));
        return result.getContent();
    }

    @Cacheable(value = "products", key = "#id")
    @Transactional(readOnly = true)
    public Product findById(Long id) {
        return repo.findById(id).orElseThrow(() ->
                new jakarta.persistence.EntityNotFoundException("Product not found: " + id));
    }

    @CacheEvict(value = "products", allEntries = true)
    @Transactional
    public Product create(Product product) {
        return repo.save(product);
    }

    @CacheEvict(value = "products", allEntries = true)
    @Transactional
    public void delete(Long id) {
        repo.deleteById(id);
    }
}
