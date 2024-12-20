// app.js

// State management
let highlights = [];
let filteredHighlights = [];
let currentHighlightIndex = -1;  // Track current highlight
let highlightHistory = [];       // Array to store navigation history
let historyPosition = -1;        // Current position in history
let filters = {
    bookTitle: 'all',
    bookAuthor: 'all',
    tags: 'all',
    color: 'all'
};

// Touch handling variables
let touchStartX = 0;
let touchEndX = 0;
const SWIPE_THRESHOLD = 50; // Minimum distance for a swipe

// DOM Elements
const highlightText = document.getElementById('highlightText');
const noteContent = document.getElementById('note');
const bookTitleSelect = document.getElementById('bookTitle');
const bookAuthorSelect = document.getElementById('bookAuthor');
const bookTagsSelect = document.getElementById('bookTags');
const highlightColorSelect = document.getElementById('highlightColor');
const highlightContainer = document.querySelector('.highlight-container');

// Navigation Functions
function navigateNext() {
    const newIndex = getNewRandomIndex(filteredHighlights.length, currentHighlightIndex);
    const newHighlight = filteredHighlights[newIndex];

    if (newHighlight && newHighlight.highlight) {
        // Add to history only when moving forward
        if (historyPosition < highlightHistory.length - 1) {
            // If we're in the middle of history, truncate forward history
            highlightHistory = highlightHistory.slice(0, historyPosition + 1);
        }
        highlightHistory.push(newIndex);
        historyPosition = highlightHistory.length - 1;

        currentHighlightIndex = newIndex;
        displayHighlight(newHighlight);
    }
}

function navigatePrevious() {
    if (historyPosition > 0) {
        historyPosition--;
        const newIndex = highlightHistory[historyPosition];
        const newHighlight = filteredHighlights[newIndex];

        if (newHighlight && newHighlight.highlight) {
            currentHighlightIndex = newIndex;
            displayHighlight(newHighlight);
        }
    }
}

// Touch and Click Event Handlers
function handleTouchStart(event) {
    touchStartX = event.touches[0].clientX;
}

function handleTouchEnd(event) {
    touchEndX = event.changedTouches[0].clientX;
    handleSwipe();
}

function handleSwipe() {
    const swipeDistance = touchEndX - touchStartX;

    if (Math.abs(swipeDistance) >= SWIPE_THRESHOLD) {
        if (swipeDistance > 0) {
            // Swipe right to left (previous)
            navigatePrevious();
        } else {
            // Swipe left to right (next)
            navigateNext();
        }
    }
}

function handleScreenClick(event) {
    const screenWidth = window.innerWidth;
    const clickX = event.clientX;

    // Click on right half of screen
    if (clickX > screenWidth / 2) {
        navigateNext();
    }
    // Click on left half of screen
    else {
        navigatePrevious();
    }
}

// Helper function to get random index different from current
function getNewRandomIndex(max, currentIndex) {
    if (max <= 1) return 0;  // If only one item, return it

    let newIndex;
    do {
        newIndex = Math.floor(Math.random() * max);
    } while (newIndex === currentIndex);

    return newIndex;
}

// Helper function to update grid layout based on note content
function updateGridLayout(hasNote) {
    if (hasNote) {
        highlightContainer.classList.remove('no-notes');
    } else {
        highlightContainer.classList.add('no-notes');
    }
}

// Load filters from the server
async function loadFilters() {
    try {
        const response = await fetch('/api/filters');
        const data = await response.json();

        // Populate book titles
        data.bookTitles.forEach(title => {
            const option = document.createElement('option');
            option.value = title;
            option.textContent = title;
            bookTitleSelect.appendChild(option);
        });

        // Populate authors
        data.bookAuthors.forEach(author => {
            const option = document.createElement('option');
            option.value = author;
            option.textContent = author;
            bookAuthorSelect.appendChild(option);
        });

        // Populate tags
        data.tags.forEach(tag => {
            const option = document.createElement('option');
            option.value = tag;
            option.textContent = tag;
            bookTagsSelect.appendChild(option);
        });

        // Populate colors
        data.colors.forEach(color => {
            const option = document.createElement('option');
            option.value = color;
            option.textContent = color;
            highlightColorSelect.appendChild(option);
        });
    } catch (error) {
        console.error('Error loading filters:', error);
    }
}

// Load highlights from the server
async function loadHighlights() {
    try {
        const response = await fetch('/api/highlights');
        highlights = await response.json();
        filterAndDisplayHighlight();
    } catch (error) {
        console.error('Error loading highlights:', error);
        highlightText.textContent = 'Error loading highlights. Please try again later.';
        updateGridLayout(false);
    }
}

// Filter highlights based on selected criteria
function filterHighlights() {
    filters = {
        bookTitle: bookTitleSelect.value,
        bookAuthor: bookAuthorSelect.value,
        tags: bookTagsSelect.value,
        color: highlightColorSelect.value
    };

    // Reset current index and history when filters change
    currentHighlightIndex = -1;
    highlightHistory = [];
    historyPosition = -1;
    filterAndDisplayHighlight();
}

// Apply filters and display current highlight
function filterAndDisplayHighlight() {
    filteredHighlights = highlights.filter(highlight => {
        if (!highlight) return false;

        const matchesTitle = filters.bookTitle === 'all' || highlight.booktitle === filters.bookTitle;
        const matchesAuthor = filters.bookAuthor === 'all' || highlight.bookauthor === filters.bookAuthor;
        const matchesColor = filters.color === 'all' || highlight.color === filters.color;
        const matchesTags = filters.tags === 'all' ||
            (highlight.tags && highlight.tags.split(',').map(t => t.trim()).includes(filters.tags));

        return matchesTitle && matchesAuthor && matchesColor && matchesTags;
    });

    if (filteredHighlights.length === 0) {
        highlightText.textContent = 'No highlights found with the selected filters.';
        noteContent.textContent = '';
        const metadata = document.getElementById('highlightMetadata');
        if (metadata) metadata.textContent = '';
        updateGridLayout(false);
        return;
    }

    // Get new random index different from current
    currentHighlightIndex = getNewRandomIndex(filteredHighlights.length, currentHighlightIndex);
    const selectedHighlight = filteredHighlights[currentHighlightIndex];

    if (selectedHighlight && selectedHighlight.highlight) {
        displayHighlight(selectedHighlight);
    } else {
        console.error('Invalid highlight data:', selectedHighlight);
        highlightText.textContent = 'Error: Could not display highlight. Please try again.';
        updateGridLayout(false);
    }

    // Set up keyboard navigation
    document.onkeydown = (e) => {
        if (e.key === 'ArrowRight') {
            navigateNext();
        }
        else if (e.key === 'ArrowLeft') {
            navigatePrevious();
        }
    };
}

// Display the selected highlight and its metadata
function displayHighlight(highlight) {
    if (!highlight || !highlight.highlight) {
        console.error('Invalid highlight data in displayHighlight:', highlight);
        updateGridLayout(false);
        return;
    }

    // Detect language and add appropriate class/attributes
    const text = highlight.highlight;
    const hasChineseCharacters = /[\u4e00-\u9fa5]/.test(text);

    // Set the highlight text with appropriate language attributes
    highlightText.textContent = text;
    if (hasChineseCharacters) {
        highlightText.setAttribute('lang', 'zh-CN');
        highlightText.classList.add('chinese-text');
    } else {
        highlightText.removeAttribute('lang');
        highlightText.classList.remove('chinese-text');
    }

    // Create or update the metadata element
    let highlightMetadata = document.getElementById('highlightMetadata');
    if (!highlightMetadata) {
        highlightMetadata = document.createElement('div');
        highlightMetadata.classList.add('highlight-metadata');
        highlightMetadata.id = 'highlightMetadata';
        // Append to highlight-card
        const highlightCard = document.querySelector('.highlight-card');
        highlightCard.appendChild(highlightMetadata);
    }

    // Set the metadata content
    const metadataContent = `
${highlight.booktitle ? `Book: ${highlight.booktitle}` : ''}
${highlight.bookauthor ? `\nAuthor: ${highlight.bookauthor}` : ''}
${highlight.tags ? `\nTags: ${highlight.tags}` : ''}
    `;

    highlightMetadata.textContent = metadataContent.trim();

    // Display note if available and update grid layout
    const note = highlight.note || '';
    noteContent.textContent = note;
    updateGridLayout(!!note);

    if (hasChineseCharacters) {
        noteContent.setAttribute('lang', 'zh-CN');
        noteContent.classList.add('chinese-text');
    } else {
        noteContent.removeAttribute('lang');
        noteContent.classList.remove('chinese-text');
    }
}

// Enhanced SearchableSelect class to handle large datasets
class SearchableSelect {
    constructor(selectElement) {
        this.selectElement = selectElement;
        this.options = Array.from(selectElement.options);
        this.createSearchableSelect();
    }

    createSearchableSelect() {
        // Hide the original select element
        this.selectElement.style.display = 'none';

        // Create container
        this.container = document.createElement('div');
        this.container.className = 'searchable-select-container';

        // Create input element
        this.input = document.createElement('input');
        this.input.type = 'text';
        this.input.className = 'searchable-select-input';
        this.input.placeholder = this.selectElement.options[this.selectElement.selectedIndex]?.textContent || 'Select an option';
        this.container.appendChild(this.input);

        // Create dropdown
        this.dropdown = document.createElement('div');
        this.dropdown.className = 'searchable-select-dropdown';

        // Append container after the select element
        this.selectElement.parentNode.insertBefore(this.container, this.selectElement.nextSibling);

        // Event listeners
        this.input.addEventListener('focus', () => this.showDropdown());
        this.input.addEventListener('input', () => this.filterOptions());
        document.addEventListener('click', (e) => this.handleDocumentClick(e));

        // Load options into the dropdown
        this.renderOptions();
    }

    renderOptions(filteredOptions = null) {
        this.dropdown.innerHTML = '';
        const optionsToRender = filteredOptions || this.options;

        // Limit the number of displayed options for performance
        const MAX_OPTIONS_DISPLAYED = 100;
        const optionsSlice = optionsToRender.slice(0, MAX_OPTIONS_DISPLAYED);

        optionsSlice.forEach(option => {
            const optionElement = document.createElement('div');
            optionElement.className = 'searchable-select-option';
            optionElement.textContent = option.textContent;
            optionElement.dataset.value = option.value;

            optionElement.addEventListener('click', () => {
                this.selectOption(optionElement.dataset.value, optionElement.textContent);
            });

            this.dropdown.appendChild(optionElement);
        });

        if (optionsToRender.length > MAX_OPTIONS_DISPLAYED) {
            const moreOptionsElement = document.createElement('div');
            moreOptionsElement.className = 'searchable-select-option';
            moreOptionsElement.textContent = 'More options available... Refine your search.';
            moreOptionsElement.style.fontStyle = 'italic';
            moreOptionsElement.style.cursor = 'default';
            this.dropdown.appendChild(moreOptionsElement);
        }

        this.container.appendChild(this.dropdown);
    }

    filterOptions() {
        const searchTerm = this.input.value.toLowerCase();
        const filteredOptions = this.options.filter(option => {
            return option.textContent.toLowerCase().includes(searchTerm);
        });
        this.renderOptions(filteredOptions);
    }

    selectOption(value, text) {
        this.selectElement.value = value;
        this.input.value = text;
        this.hideDropdown();
        // Trigger change event
        const event = new Event('change');
        this.selectElement.dispatchEvent(event);
    }

    showDropdown() {
        this.dropdown.classList.add('active');
    }

    hideDropdown() {
        this.dropdown.classList.remove('active');
    }

    handleDocumentClick(e) {
        if (!this.container.contains(e.target)) {
            this.hideDropdown();
        }
    }
}

// Initialize searchable selects
function initializeSearchableSelects() {
    const selects = [
        document.getElementById('bookTitle'),
        document.getElementById('bookAuthor'),
        document.getElementById('bookTags'),
        document.getElementById('highlightColor')
    ];

    selects.forEach(select => {
        if (select) {
            new SearchableSelect(select);
        }
    });
}

// Initialize the application
async function init() {
    await loadFilters();
    await loadHighlights();

    // Initialize searchable selects after filters are loaded
    initializeSearchableSelects();

    // Add event listeners for filter changes
    bookTitleSelect.addEventListener('change', filterHighlights);
    bookAuthorSelect.addEventListener('change', filterHighlights);
    bookTagsSelect.addEventListener('change', filterHighlights);
    highlightColorSelect.addEventListener('change', filterHighlights);

    // Add touch and click event listeners
    document.addEventListener('touchstart', handleTouchStart, false);
    document.addEventListener('touchend', handleTouchEnd, false);
    document.addEventListener('click', handleScreenClick, false);
}

// Start the application
init();

