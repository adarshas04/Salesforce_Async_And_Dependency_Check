import { LightningElement, track } from 'lwc';
import getAllObjects from '@salesforce/apex/ObjectMetadataController.getAllObjects';
import getFieldsForObject from '@salesforce/apex/ObjectMetadataController.getFieldsForObject';
import getCategoryDefinitions from '@salesforce/apex/ObjectMetadataController.getCategoryDefinitions';
import analyzeFieldUsage from '@salesforce/apex/ObjectMetadataController.analyzeFieldUsage';

export default class ObjectFieldSelector extends LightningElement {
    // --- Object selection ---
    @track objectOptions = [];
    selectedObjectApiName;

    // --- Field selection ---
    @track fieldOptions = [];
    @track selectedFieldApiNames = [];

    // --- Category checklist (default vs optional, server-driven) ---
    @track categoryOptions = []; // { categoryKey, label, defaultSelected, tier }
    selectedCategories = [];

    // --- Results ---
    @track resultRows = [];
    @track groupedResults = [];
    @track categoryErrors = [];
    @track loadingStatusMessage = '';
    isLoading = false;
    hasAnalyzed = false;
    loadingMessageIndex = 0;
    loadingMessageTimer;

    connectedCallback() {
        this.loadObjects();
        this.loadCategoryDefinitions();
    }

    disconnectedCallback() {
        this.stopLoadingNarration();
    }

    async loadObjects() {
        try {
            const objects = await getAllObjects();
            this.objectOptions = objects.map((o) => ({
                label: o.label,
                value: o.apiName
            }));
        } catch (error) {
            this.showToastSafe('Error loading objects', error);
        }
    }

    async loadCategoryDefinitions() {
        try {
            const categories = await getCategoryDefinitions();
            this.categoryOptions = categories.map((category) => ({
                ...category,
                checked: category.defaultSelected
            }));
            // Pre-select DEFAULT_ON tier categories - this is what gives
            // the "flexible UX": fast, high-signal categories run
            // automatically, while expensive/lower-priority ones (Reports,
            // Workflow) stay opt-in.
            this.selectedCategories = this.categoryOptions
                .filter((c) => c.defaultSelected)
                .map((c) => c.categoryKey);
        } catch (error) {
            this.showToastSafe('Error loading category definitions', error);
        }
    }

    handleObjectChange(event) {
        this.selectedObjectApiName = event.detail.value;
        this.selectedFieldApiNames = [];
        this.fieldOptions = [];
        this.resultRows = [];
        this.groupedResults = [];
        this.hasAnalyzed = false;
        this.loadFieldsForSelectedObject();
    }

    async loadFieldsForSelectedObject() {
        if (!this.selectedObjectApiName) {
            this.fieldOptions = [];
            return;
        }

        try {
            const fields = await getFieldsForObject({ objectApiName: this.selectedObjectApiName });
            this.fieldOptions = fields
                .map((f) => ({ label: `${f.label} (${f.apiName})`, value: f.apiName }))
                .sort((a, b) => a.label.localeCompare(b.label));
        } catch (error) {
            this.showToastSafe('Error loading fields', error);
        }
    }

    handleFieldSelectionChange(event) {
        this.selectedFieldApiNames = event.detail.value;
    }

    handleCategoryToggle(event) {
        const key = event.target.dataset.categoryKey;
        const checked = event.target.checked;
        this.categoryOptions = this.categoryOptions.map((category) =>
            category.categoryKey === key
                ? { ...category, checked }
                : category
        );
        if (checked && !this.selectedCategories.includes(key)) {
            this.selectedCategories = [...this.selectedCategories, key];
        } else if (!checked) {
            this.selectedCategories = this.selectedCategories.filter((k) => k !== key);
        }
    }

    get isAnalyzeDisabled() {
        return (
            !this.selectedObjectApiName ||
            this.selectedFieldApiNames.length === 0 ||
            this.selectedCategories.length === 0 ||
            this.isLoading
        );
    }

    async handleAnalyzeClick() {
        this.isLoading = true;
        this.hasAnalyzed = false;
        this.resultRows = [];
        this.groupedResults = [];
        this.categoryErrors = [];
        this.startLoadingNarration();

        try {
            const response = await analyzeFieldUsage({
                objectApiName: this.selectedObjectApiName,
                fieldApiNames: this.selectedFieldApiNames,
                selectedCategories: this.selectedCategories
            });

            const rows = [];
            Object.keys(response.resultsByCategory || {}).forEach((category) => {
                (response.resultsByCategory[category] || []).forEach((usage) => {
                    rows.push({
                        id: `${category}-${usage.componentType}-${usage.componentName}-${usage.fieldApiName}`,
                        category,
                        ...usage
                    });
                });
            });
            this.resultRows = rows;
            this.groupedResults = this.buildGroupedResults(rows);

            this.categoryErrors = Object.keys(response.categoryErrors || {}).map((category) => ({
                category,
                message: response.categoryErrors[category]
            }));
        } catch (error) {
            this.showToastSafe('Error analyzing field usage', error);
        } finally {
            this.stopLoadingNarration();
            this.isLoading = false;
            this.hasAnalyzed = true;
        }
    }

    get hasResults() {
        return this.groupedResults.length > 0;
    }

    get hasNoResults() {
        return (
            this.hasAnalyzed &&
            !this.isLoading &&
            this.groupedResults.length === 0 &&
            this.categoryErrors.length === 0
        );
    }

    get selectedFieldCountLabel() {
        const count = this.selectedFieldApiNames.length;
        return count === 1 ? '1 field selected' : `${count} fields selected`;
    }

    get selectedCategoryCountLabel() {
        const count = this.selectedCategories.length;
        return count === 1 ? '1 category analyzed' : `${count} categories analyzed`;
    }

    get selectedCategoryPills() {
        return this.selectedCategories.map((categoryKey) => ({
            id: `selected-${categoryKey}`,
            label: this.formatCategoryLabel(categoryKey)
        }));
    }

    get emptyCategoryPills() {
        const categoriesWithResults = new Set(this.resultRows.map((row) => row.category));
        return this.selectedCategories
            .filter((categoryKey) => !categoriesWithResults.has(categoryKey))
            .map((categoryKey) => ({
                id: `empty-${categoryKey}`,
                label: this.formatCategoryLabel(categoryKey)
            }));
    }

    get loadingCategorySummary() {
        return this.selectedCategories.map((categoryKey) => this.formatCategoryLabel(categoryKey)).join(', ');
    }

    get hasOptionalDeepScanSelected() {
        return this.selectedCategories.some((categoryKey) =>
            ['REPORT', 'REPORT_TYPE', 'WORKFLOW_PROCESS'].includes(categoryKey)
        );
    }

    buildGroupedResults(rows) {
        const fieldMap = new Map();

        rows.forEach((row) => {
            if (!fieldMap.has(row.fieldApiName)) {
                fieldMap.set(row.fieldApiName, {
                    id: `field-${row.fieldApiName}`,
                    fieldApiName: row.fieldApiName,
                    totalDependencies: 0,
                    categoryCount: 0,
                    categoryGroups: [],
                    categoryMap: new Map()
                });
            }

            const fieldGroup = fieldMap.get(row.fieldApiName);
            fieldGroup.totalDependencies += 1;

            if (!fieldGroup.categoryMap.has(row.category)) {
                fieldGroup.categoryMap.set(row.category, {
                    id: `${row.fieldApiName}-${row.category}`,
                    category: row.category,
                    title: this.formatCategoryLabel(row.category),
                    totalDependencies: 0,
                    componentTypes: new Set(),
                    usages: []
                });
            }

            const categoryGroup = fieldGroup.categoryMap.get(row.category);
            categoryGroup.totalDependencies += 1;
            categoryGroup.componentTypes.add(row.componentType);
            categoryGroup.usages.push({
                ...row,
                metaLabel: `${row.componentType} • ${this.formatCategoryLabel(row.category)}`
            });
        });

        return this.selectedFieldApiNames
            .filter((fieldApiName) => fieldMap.has(fieldApiName))
            .map((fieldApiName) => {
                const fieldGroup = fieldMap.get(fieldApiName);
                const categoryGroups = Array.from(fieldGroup.categoryMap.values())
                    .map((categoryGroup) => ({
                        ...categoryGroup,
                        componentTypeSummary: Array.from(categoryGroup.componentTypes).sort().join(', '),
                        usages: categoryGroup.usages.sort((left, right) =>
                            `${left.componentType}${left.componentName}`.localeCompare(
                                `${right.componentType}${right.componentName}`
                            )
                        )
                    }))
                    .sort((left, right) => left.title.localeCompare(right.title));

                return {
                    id: fieldGroup.id,
                    fieldApiName: fieldGroup.fieldApiName,
                    totalDependencies: fieldGroup.totalDependencies,
                    categoryCount: categoryGroups.length,
                    summaryLabel: `${fieldGroup.totalDependencies} dependenc${
                        fieldGroup.totalDependencies === 1 ? 'y' : 'ies'
                    } across ${categoryGroups.length} categor${categoryGroups.length === 1 ? 'y' : 'ies'}`,
                    categoryGroups
                };
            });
    }

    formatCategoryLabel(categoryKey) {
        return String(categoryKey || '')
            .toLowerCase()
            .split('_')
            .map((segment) => segment.charAt(0).toUpperCase() + segment.slice(1))
            .join(' ');
    }

    startLoadingNarration() {
        const messages = this.buildLoadingMessages();
        this.loadingMessageIndex = 0;
        this.loadingStatusMessage = messages[0];
        this.loadingMessageTimer = window.setInterval(() => {
            this.loadingMessageIndex = (this.loadingMessageIndex + 1) % messages.length;
            this.loadingStatusMessage = messages[this.loadingMessageIndex];
        }, 1600);
    }

    stopLoadingNarration() {
        if (this.loadingMessageTimer) {
            window.clearInterval(this.loadingMessageTimer);
            this.loadingMessageTimer = null;
        }
        this.loadingStatusMessage = '';
        this.loadingMessageIndex = 0;
    }

    buildLoadingMessages() {
        const fieldCount = this.selectedFieldApiNames.length;
        const fieldLabel = fieldCount === 1 ? 'field' : 'fields';
        const messages = [
            `Preparing dependency scan for ${this.selectedObjectApiName}...`,
            `Checking ${fieldCount} selected ${fieldLabel} across metadata categories...`,
            'Searching Apex, layouts, flows, and page definitions...'
        ];

        if (this.selectedCategories.includes('REPORT') || this.selectedCategories.includes('REPORT_TYPE')) {
            messages.push('Reviewing reporting metadata and accessible report definitions...');
        }

        if (this.selectedCategories.includes('WORKFLOW_PROCESS')) {
            messages.push('Scanning legacy workflow/process dependencies...');
        }

        messages.push(
            this.hasOptionalDeepScanSelected
                ? 'Finishing deeper dependency checks and grouping the results...'
                : 'Grouping dependency matches into a readable result view...'
        );

        return messages;
    }

    showToastSafe(title, error) {
        // eslint-disable-next-line no-console
        console.error(title, error);
        this.dispatchEvent(
            new CustomEvent('errornotify', {
                detail: { title, message: error?.body?.message || error?.message || 'Unknown error' }
            })
        );
    }
}
